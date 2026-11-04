const { Client } = require('ssh2');
const fs = require('fs');
const logger = require('../utils/logger');
const config = require('../config');

// Exit code used when a command is killed for exceeding its timeout, matching the
// convention of coreutils `timeout`.
const TIMEOUT_EXIT_CODE = 124;

/**
 * Execute a command on a remote SSH server
 * @param {string} command - The command to execute
 * @param {Object} [options] - Execution options
 * @param {number} [options.timeoutMs] - Kill the command after this many milliseconds
 *   and resolve with exit code 124. Omit for no timeout (the historical behaviour,
 *   which the exam setup and cleanup calls still rely on).
 * @returns {Promise<Object>} The result of the command execution
 */
async function executeCommand(command, options = {}) {
  const { timeoutMs } = options;
  logger.info(`Executing command: ${command}`);
  
  return new Promise((resolve, reject) => {
    const conn = new Client();
    let stdout = '';
    let stderr = '';
    let timer = null;
    let settled = false;
    
    // Guard every exit path: once the timer has fired and resolved, the stream's own
    // 'close' must not resolve a second time.
    const finish = (result) => {
      if (settled) {
        return;
      }
      settled = true;
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
      conn.end();
      resolve(result);
    };
    
    const fail = (err) => {
      if (settled) {
        return;
      }
      settled = true;
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
      reject(err);
    };
    
    conn.on('ready', () => {
      logger.info('SSH connection established');
      
      conn.exec(command, (err, stream) => {
        if (err) {
          logger.error('Failed to execute command', { error: err.message });
          conn.end();
          return fail(err);
        }
        
        if (timeoutMs) {
          timer = setTimeout(() => {
            logger.warn(`Command timed out after ${timeoutMs}ms, terminating: ${command}`);
            // Settle first, then tear down. Closing the channel makes the stream emit
            // its own 'close' with a null exit code, and if that landed first it would
            // win the race and the timeout would be indistinguishable from an ordinary
            // failed check in the logs.
            finish({
              exitCode: TIMEOUT_EXIT_CODE,
              stdout,
              stderr,
              timedOut: true
            });
            // finish() has already called conn.end(); closing the channel as well covers
            // the case where the connection teardown alone leaves the remote process up.
            try {
              stream.close();
            } catch (closeErr) {
              logger.error('Failed to close SSH stream on timeout', { error: closeErr.message });
            }
          }, timeoutMs);
        }
        
        stream.on('data', (data) => {
          stdout += data.toString();
        });
        
        stream.stderr.on('data', (data) => {
          stderr += data.toString();
        });
        
        stream.on('close', (code) => {
          logger.info(`Command execution completed with exit code: ${code}`);
          finish({
            exitCode: code,
            stdout,
            stderr
          });
        });
      });
    });
    
    conn.on('error', (err) => {
      logger.error('SSH connection error', { error: err.message });
      fail(err);
    });
    
    // Configure connection for jumphost which accepts passwordless authentication
    const connectionConfig = {
      host: config.ssh.host,
      port: config.ssh.port,
      username: config.ssh.username,
      // For passwordless authentication
      readyTimeout: 30000, // Increase timeout for slow connections
    };
    
    // Add authentication methods if available
    if (config.ssh.privateKeyPath) {
      logger.info('Using private key authentication');
      try {
        connectionConfig.privateKey = fs.readFileSync(config.ssh.privateKeyPath);
      } catch (err) {
        logger.error('Failed to read private key', { error: err.message });
        return fail(new Error(`Failed to read private key: ${err.message}`));
      }
    } else if (config.ssh.password) {
      logger.info('Using password authentication');
      connectionConfig.password = config.ssh.password;
    } else {
      logger.info('Using passwordless authentication');
      // In production environment, this typically uses SSH agent forwarding
      // or hostbased authentication which is configured in SSH config
    }
    
    conn.connect(connectionConfig);
  });
}

module.exports = {
  executeCommand,
  TIMEOUT_EXIT_CODE
}; 