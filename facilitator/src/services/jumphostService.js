/**
 * Jumphost Service
 * 
 * This service handles SSH connections to the jumphost for exam environment
 * preparation and cleanup operations. It provides two main functionalities:
 * 1. Setting up the exam environment (prepare-exam-env)
 * 2. Cleaning up the exam environment after the exam is completed
 * 3. Evaluating exam by running verification scripts
 */

const sshService = require('./sshService');
const redisClient = require('../utils/redisClient');
const logger = require('../utils/logger');
const remoteDesktopService = require('./remoteDesktopService');

// A CKA lab is 50-100 verification scripts, each one a fresh SSH session running a
// kubectl-heavy shell script. Run a few at a time: questions are namespace-isolated
// by design, so the scripts are independent of one another.
const VALIDATION_CONCURRENCY = parseInt(process.env.VALIDATION_CONCURRENCY || '4', 10);
// Backstop for a script that hangs. Without it a single wedged script stalls the whole
// evaluation forever and the result is never written, which the results page can only
// report as "still evaluating".
//
// The limit is enforced twice. `timeout` on the jumphost is the one that matters: it
// runs the script in its own process group and signals the group, so a script blocked
// in `sleep` or `kubectl` dies along with its children. Closing the SSH channel from
// this end would not do that -- exec sessions get no PTY, so nothing sends SIGHUP and
// the remote process keeps running for the rest of the evaluation.
const VALIDATION_SCRIPT_TIMEOUT_SECONDS = parseInt(
  process.env.VALIDATION_SCRIPT_TIMEOUT_SECONDS || '90', 10
);
// Grace between SIGTERM and SIGKILL on the jumphost.
const VALIDATION_SCRIPT_KILL_GRACE_SECONDS = 5;
// The client-side limit only covers a wedged SSH channel, where the remote `timeout`
// can no longer report back. Keep it comfortably later so the remote one always wins
// and the exit code stays meaningful.
const VALIDATION_SCRIPT_TIMEOUT_MS =
  (VALIDATION_SCRIPT_TIMEOUT_SECONDS + VALIDATION_SCRIPT_KILL_GRACE_SECONDS + 15) * 1000;

/**
 * Run tasks with a bounded number in flight, preserving input order in the output.
 *
 * @param {Array} items - The items to process
 * @param {number} limit - Maximum number of tasks running at once
 * @param {Function} worker - async (item, index) => result
 * @returns {Promise<Array>} Results, in the same order as `items`
 */
async function runWithConcurrency(items, limit, worker) {
  const results = new Array(items.length);
  let nextIndex = 0;

  const runner = async () => {
    while (true) {
      const index = nextIndex++;
      if (index >= items.length) {
        return;
      }
      results[index] = await worker(items[index], index);
    }
  };

  const workerCount = Math.max(1, Math.min(limit, items.length));
  await Promise.all(Array.from({ length: workerCount }, runner));

  return results;
}

/**
 * Prepare the exam environment on the jumphost
 * 
 * This method executes the "prepare-exam-env" command on the jumphost
 * to set up the required number of nodes for the exam. It also updates
 * the exam status in Redis to reflect the preparation process.
 * 
 * @param {string} examId - The ID of the exam to prepare
 * @param {number} nodeCount - The number of nodes to prepare (default: 1)
 * @param {string} clusterType - Cluster flavour to create, "k3d" or "kind" (default: k3d)
 * @param {string} auxClusterType - Auxiliary cluster flavour, "kind" or "" for none
 * @param {string} auxNodeImage - kind node image for the auxiliary cluster, "" for the pinned default
 * @returns {Promise<Object>} Result object with success status and data
 */
async function setupExamEnvironment(examId, nodeCount = 1, clusterType = 'k3d', auxClusterType = '', auxNodeImage = '') {
  try {
    // Update exam status to PREPARING
    await redisClient.persistExamStatus(examId, 'PREPARING');
    logger.info(`Started preparing environment for exam ${examId} with ${nodeCount} nodes on a ${clusterType} cluster` +
      (auxClusterType ? ` plus a ${auxClusterType} auxiliary cluster` : '') +
      (auxClusterType && auxNodeImage ? ` on ${auxNodeImage}` : ''));
    
    //restart vnc session
    await remoteDesktopService.restartVncSession();

    // Execute the prepare-exam-env command on the jumphost. The auxiliary cluster
    // flavour and its node image are the last two arguments and are omitted
    // entirely when a lab does not ask for them, so the command every existing lab
    // sends is unchanged. The image is positional after the flavour, so it can only
    // ever be sent alongside one.
    const command = `prepare-exam-env ${nodeCount} ${examId} ${clusterType}` +
      (auxClusterType ? ` ${auxClusterType}` : '') +
      (auxClusterType && auxNodeImage ? ` ${auxNodeImage}` : '');
    
    logger.info(`Executing command on jumphost: ${command}`);
    const result = await sshService.executeCommand(command);
    
    logger.info('Command : prepare-exam-env, host: jumphost, result', { exitCode: result.exitCode });
    logger.info(result.stdout);

    if (result.exitCode !== 0) {
      logger.error('Failed to prepare exam environment', {
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode
      });
      
      await redisClient.persistExamStatus(examId, 'PREPARATION_FAILED');

      return {
        success: false,
        error: 'Failed to prepare exam environment',
        details: {
          stdout: result.stdout,
          stderr: result.stderr,
          exitCode: result.exitCode
        }
      };
    }
    
    // Update exam status to READY
    await redisClient.persistExamStatus(examId, 'READY');
    logger.info(`Successfully prepared environment for exam ${examId}`);

    return {
      success: true,
      message: 'Exam environment prepared successfully',
      details: {
        stdout: result.stdout
      }
    };
  } catch (error) {
    logger.error('Error preparing exam environment', { error: error.message });
    
    // Update exam status to PREPARATION_FAILED
    await redisClient.persistExamStatus(examId, 'PREPARATION_FAILED');
    
    return {
      success: false,
      error: 'Error preparing exam environment',
      message: error.message
    };
  }
}

/**
 * Clean up the exam environment on the jumphost
 * 
 * This method executes the cleanup command on the jumphost to clean up
 * resources used by the exam. It also updates the exam status in Redis.
 * 
 * @param {string} examId - The ID of the exam to clean up
 * @returns {Promise<Object>} Result object with success status and data
 */
async function cleanupExamEnvironment(examId) {
  try {
    // Update exam status to CLEANING_UP
    await redisClient.persistExamStatus(examId, 'CLEANING_UP');
    logger.info(`Started cleaning up environment for exam ${examId}`);

    // Execute the cleanup command on the jumphost
    // Assuming a cleanup script exists on the jumphost
    const command = 'cleanup-exam-env';
    
    logger.info(`Executing command on jumphost: ${command}`);
    const result = await sshService.executeCommand(command);

    logger.info('Command : cleanup-exam-env, host: jumphost, result', { exitCode: result.exitCode });
    logger.info(result.stdout);


    if (result.exitCode !== 0) {
      logger.error('Failed to clean up exam environment', {
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode
      });

      await redisClient.persistExamStatus(examId, 'CLEANUP_FAILED');
      
      return {
        success: false,
        error: 'Failed to clean up exam environment',
        details: {
          stdout: result.stdout,
          stderr: result.stderr,
          exitCode: result.exitCode
        }
      };
    }
    
    // Update exam status to COMPLETED
    await redisClient.persistExamStatus(examId, 'COMPLETED');
    logger.info(`Successfully cleaned up environment for exam ${examId}`);
    return {
      success: true,
      message: 'Exam environment cleaned up successfully',
      details: {
        stdout: result.stdout
      }
    };
  } catch (error) {
    logger.error('Error cleaning up exam environment', { error: error.message });
    
    // Update exam status to CLEANUP_FAILED
    await redisClient.persistExamStatus(examId, 'CLEANUP_FAILED');
    
    return {
      success: false,
      error: 'Error cleaning up exam environment',
      message: error.message
    };
  }
}

/**
 * Evaluate exam by running verification scripts on jumphost
 * 
 * This method executes verification scripts for each question and its steps
 * to validate student solutions. It updates the exam status during evaluation
 * and stores the final results in Redis.
 * 
 * @param {string} examId - The ID of the exam to evaluate
 * @param {Array} questions - Array of questions with verification steps
 * @returns {Promise<Object>} Result object with evaluation data
 */
async function evaluateExamOnJumphost(examId, questions) {
  try {
    //log number of questions 
    logger.info(`Number of questions to evaluate: ${questions.length}`);

    // Flatten every (question, verification) pair into one work list so the whole exam
    // can be evaluated with a bounded pool instead of strictly one script at a time.
    const tasks = [];
    questions.forEach((question, questionIndex) => {
      logger.info(`Question ID: ${question.id}`);
      logger.info(`Namespace: ${question.namespace}`);
      logger.info(`Question: ${question.question}`);
      logger.info(`Concepts: ${question.concepts ? question.concepts.join(', ') : 'None'}`);

      (question.verification || []).forEach((verification) => {
        tasks.push({ question, questionIndex, verification });
      });
    });

    logger.info(
      `Running ${tasks.length} verification scripts with concurrency ${VALIDATION_CONCURRENCY} ` +
      `and a ${VALIDATION_SCRIPT_TIMEOUT_SECONDS}s per-script timeout`
    );

    const taskResults = await runWithConcurrency(tasks, VALIDATION_CONCURRENCY, async (task) => {
      const { question, verification } = task;
      const verificationScript = verification.verificationScriptFile;
      const weightage = parseInt(verification.weightage, 10);

      // Record the verification result without logs
      const record = {
        id: verification.id,
        description: verification.description,
        validAnswer: false,
        weightage: weightage,
        score: 0
      };

      try {
        // Execute the verification script directly using sshService
        // The script is located on the jumphost at the specified path
        const scriptPath = `/tmp/exam-assets/scripts/validation/${verificationScript}`;

        // Add KUBECONFIG environment variable to ensure all verifications use the correct kube config
        const commandWithKubeconfig =
          `export KUBECONFIG=/home/candidate/.kube/kubeconfig && ` +
          `timeout -k ${VALIDATION_SCRIPT_KILL_GRACE_SECONDS} ` +
          `${VALIDATION_SCRIPT_TIMEOUT_SECONDS} ${scriptPath}`;

        logger.info(`Executing verification script: ${scriptPath} with KUBECONFIG set`);
        const result = await sshService.executeCommand(commandWithKubeconfig, {
          timeoutMs: VALIDATION_SCRIPT_TIMEOUT_MS
        });

        // Determine if the verification passed
        const isValid = result.exitCode === 0;
        record.validAnswer = isValid;
        record.score = isValid ? weightage : 0;

        // Log info about verification
        logger.info(`Verification ID: ${verification.id}`);
        logger.info(`Description: ${verification.description}`);
        logger.info(`Weightage: ${weightage}`);
        logger.info(`Script Path: ${scriptPath}`);

        // `timeout` reports 124 the same way the SSH-side backstop does, so both routes
        // land here. Distinguish a wedged script from a genuinely failed check in the
        // logs, since both score 0 and the candidate is shown neither.
        if (result.timedOut || result.exitCode === sshService.TIMEOUT_EXIT_CODE) {
          logger.warn(
            `Verification ${verification.id} for question ${question.id} TIMED OUT ` +
            `after ${VALIDATION_SCRIPT_TIMEOUT_SECONDS}s: ${scriptPath}` +
            (result.timedOut ? ' (SSH channel backstop)' : '')
          );
        }

        // Log the result for debugging but don't include in response
        // Only include stderr in logs when exit code is 1 (failed verification)
        const logData = {
          stdout: result.stdout,
          exitCode: result.exitCode
        };

        // Only include stderr in logs when verification fails
        if (result.exitCode !== 0) {
          logData.stderr = result.stderr;
        }

        logger.info(`Verification ${verification.id} for question ${question.id}: ${isValid ? 'PASSED' : 'FAILED'}`, logData);
      } catch (error) {
        logger.error(`Error executing verification script for question ${question.id}`, {
          error: error.message, verification: verification.id
        });
        // The record already carries the failed defaults.
      }

      return record;
    });

    // Reassemble in question order. Both the work list and the results share the input
    // ordering, so the per-question arrays come out exactly as the serial loop built them.
    const questionResults = questions.map((question) => ({
      id: question.id,
      namespace: question.namespace,
      question: question.question,
      concepts: question.concepts || [],
      verificationResults: []
    }));

    let totalScore = 0;
    let totalPossibleScore = 0;

    tasks.forEach((task, index) => {
      const record = taskResults[index];
      totalPossibleScore += record.weightage;
      totalScore += record.score;
      questionResults[task.questionIndex].verificationResults.push(record);
    });

    const evaluationResults = questionResults;

    // Calculate percentage score
    const percentageScore = totalPossibleScore > 0 ? 
      Math.round((totalScore / totalPossibleScore) * 100) : 0;

    // Assign rank based on percentage score
    let rank = 'low';
    if (percentageScore >= 80) {
      rank = 'high';
    } else if (percentageScore >= 60) {
      rank = 'medium';
    }

    // Prepare final evaluation result
    const finalResult = {
      examId,
      status: 'EVALUATED',
      totalScore,
      totalPossibleScore,
      percentageScore,
      rank,
      evaluationResults,
      completedAt: new Date().toISOString()
    };

    // Store result in Redis using the new persistExamResult method
    await redisClient.persistExamResult(examId, finalResult);
    
    // Update exam status to EVALUATED
    await redisClient.updateExamStatus(examId, 'EVALUATED');
    
    logger.info(`Exam ${examId} evaluation completed with score: ${percentageScore}%`);

    return {
      success: true,
      data: finalResult
    };
  } catch (error) {
    logger.error(`Error in exam evaluation for exam ${examId}`, { error: error.message });
    // Update exam status to EVALUATION_FAILED
    await redisClient.updateExamStatus(examId, 'EVALUATION_FAILED');

    return {
      success: false,
      error: 'Evaluation failed',
      message: error.message
    };
  }
}

module.exports = {
  setupExamEnvironment,
  cleanupExamEnvironment,
  evaluateExamOnJumphost
}; 