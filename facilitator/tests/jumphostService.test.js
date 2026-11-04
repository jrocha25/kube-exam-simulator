/**
 * Tests for Jumphost Service
 * 
 * These tests verify that the jumphost service can properly
 * set up and clean up exam environments.
 */

const jumphostService = require('../src/services/jumphostService');
const sshService = require('../src/services/sshService');
const redisClient = require('../src/utils/redisClient');

// Mock dependencies
jest.mock('../src/services/sshService');
jest.mock('../src/utils/redisClient');

describe('Jumphost Service', () => {
  beforeEach(() => {
    // Clear all mocks before each test
    jest.clearAllMocks();
  });

  describe('setupExamEnvironment', () => {
    it('should update exam status to PREPARING, execute the prepare command, and update status to READY on success', async () => {
      // Mock successful SSH command execution
      sshService.executeCommand.mockResolvedValueOnce({
        exitCode: 0,
        stdout: 'Environment prepared successfully',
        stderr: ''
      });

      // Call the function
      const result = await jumphostService.setupExamEnvironment('test-exam-id', 2);

      // Verify Redis status updates
      expect(redisClient.persistExamStatus).toHaveBeenCalledTimes(2);
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(1, 'test-exam-id', 'PREPARING');
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(2, 'test-exam-id', 'READY');

      // Verify SSH command execution
      expect(sshService.executeCommand).toHaveBeenCalledWith('prepare-exam-env 2');

      // Verify result
      expect(result).toEqual({
        success: true,
        message: 'Exam environment prepared successfully',
        details: {
          stdout: 'Environment prepared successfully'
        }
      });
    });

    it('should handle command execution failure', async () => {
      // Mock failed SSH command execution
      sshService.executeCommand.mockResolvedValueOnce({
        exitCode: 1,
        stdout: '',
        stderr: 'Failed to prepare environment'
      });

      // Call the function
      const result = await jumphostService.setupExamEnvironment('test-exam-id');

      // Verify Redis status updates
      expect(redisClient.persistExamStatus).toHaveBeenCalledTimes(2);
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(1, 'test-exam-id', 'PREPARING');
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(2, 'test-exam-id', 'PREPARATION_FAILED');

      // Verify result
      expect(result).toEqual({
        success: false,
        error: 'Failed to prepare exam environment',
        details: {
          stdout: '',
          stderr: 'Failed to prepare environment',
          exitCode: 1
        }
      });
    });

    it('should handle unexpected errors', async () => {
      // Mock exception
      const error = new Error('Unexpected error');
      sshService.executeCommand.mockRejectedValueOnce(error);

      // Call the function
      const result = await jumphostService.setupExamEnvironment('test-exam-id');

      // Verify Redis status updates
      expect(redisClient.persistExamStatus).toHaveBeenCalledTimes(2);
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(1, 'test-exam-id', 'PREPARING');
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(2, 'test-exam-id', 'PREPARATION_FAILED');

      // Verify result
      expect(result).toEqual({
        success: false,
        error: 'Error preparing exam environment',
        message: 'Unexpected error'
      });
    });
  });

  describe('cleanupExamEnvironment', () => {
    it('should update exam status to CLEANING_UP, execute the cleanup command, and update status to COMPLETED on success', async () => {
      // Mock successful SSH command execution
      sshService.executeCommand.mockResolvedValueOnce({
        exitCode: 0,
        stdout: 'Environment cleaned up successfully',
        stderr: ''
      });

      // Call the function
      const result = await jumphostService.cleanupExamEnvironment('test-exam-id');

      // Verify Redis status updates
      expect(redisClient.persistExamStatus).toHaveBeenCalledTimes(2);
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(1, 'test-exam-id', 'CLEANING_UP');
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(2, 'test-exam-id', 'COMPLETED');

      // Verify SSH command execution
      expect(sshService.executeCommand).toHaveBeenCalledWith('cleanup-exam-env');

      // Verify result
      expect(result).toEqual({
        success: true,
        message: 'Exam environment cleaned up successfully',
        details: {
          stdout: 'Environment cleaned up successfully'
        }
      });
    });

    it('should handle command execution failure', async () => {
      // Mock failed SSH command execution
      sshService.executeCommand.mockResolvedValueOnce({
        exitCode: 1,
        stdout: '',
        stderr: 'Failed to clean up environment'
      });

      // Call the function
      const result = await jumphostService.cleanupExamEnvironment('test-exam-id');

      // Verify Redis status updates
      expect(redisClient.persistExamStatus).toHaveBeenCalledTimes(2);
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(1, 'test-exam-id', 'CLEANING_UP');
      expect(redisClient.persistExamStatus).toHaveBeenNthCalledWith(2, 'test-exam-id', 'CLEANUP_FAILED');

      // Verify result
      expect(result).toEqual({
        success: false,
        error: 'Failed to clean up exam environment',
        details: {
          stdout: '',
          stderr: 'Failed to clean up environment',
          exitCode: 1
        }
      });
    });
  });
}); 