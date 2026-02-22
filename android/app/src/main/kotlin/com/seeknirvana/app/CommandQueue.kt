package com.seeknirvana.app

import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Command queue system to ensure 300ms spacing between BLE commands
 * as per Yongxin SDK best practices documentation.
 * 
 * Requirements:
 * - 3-second delay after BLE connection before first command
 * - 300ms minimum spacing between consecutive commands
 * - Sequential execution (no concurrent commands)
 */
class CommandQueue {
    companion object {
        private const val TAG = "CommandQueue"
        private const val COMMAND_INTERVAL_MS = 300L
        private const val POST_CONNECTION_DELAY_MS = 3000L
    }
    
    private val handler = Handler(Looper.getMainLooper())
    private var lastCommandTime = 0L
    private var isPostConnectionDelayComplete = false
    private val pendingCommands = mutableListOf<() -> Unit>()
    private var isPaused = false
    
    /**
     * Must be called when BLE connection succeeds (code == 7)
     * Starts the 3-second post-connection delay before accepting commands.
     */
    fun onConnectionSucceeded() {
        Log.i(TAG, "Connection succeeded, starting $POST_CONNECTION_DELAY_MS ms delay")
        isPostConnectionDelayComplete = false
        isPaused = false
        lastCommandTime = System.currentTimeMillis()
        
        handler.postDelayed({
            isPostConnectionDelayComplete = true
            Log.i(TAG, "Post-connection delay complete, processing ${pendingCommands.size} pending commands")
            processPendingCommands()
        }, POST_CONNECTION_DELAY_MS)
    }
    
    /**
     * Enqueue a command with proper timing.
     * Commands are automatically delayed if within 300ms of previous command.
     * Commands sent during post-connection delay are queued and executed after.
     */
    fun enqueue(command: () -> Unit) {
        if (isPaused) {
            Log.d(TAG, "Command queued (queue is paused)")
            pendingCommands.add(command)
            return
        }
        
        if (!isPostConnectionDelayComplete) {
            Log.d(TAG, "Command queued (waiting for post-connection delay)")
            pendingCommands.add(command)
            return
        }
        
        executeWithTiming(command)
    }
    
    /**
     * Enqueue a command with higher priority - executes after current command
     * but before other queued commands.
     */
    fun enqueuePriority(command: () -> Unit) {
        if (!isPostConnectionDelayComplete || isPaused) {
            // Insert at front of pending queue
            pendingCommands.add(0, command)
            Log.d(TAG, "Priority command queued")
            return
        }
        
        executeWithTiming(command)
    }
    
    private fun executeWithTiming(command: () -> Unit) {
        val now = System.currentTimeMillis()
        val timeSinceLastCommand = now - lastCommandTime
        val delay = if (timeSinceLastCommand < COMMAND_INTERVAL_MS) {
            COMMAND_INTERVAL_MS - timeSinceLastCommand
        } else 0
        
        if (delay > 0) {
            Log.d(TAG, "Delaying command by ${delay}ms for proper spacing")
        }
        
        handler.postDelayed({
            try {
                command()
            } catch (e: Exception) {
                Log.e(TAG, "Command execution failed", e)
            }
            lastCommandTime = System.currentTimeMillis()
        }, delay)
    }
    
    private fun processPendingCommands() {
        val commandsToProcess = pendingCommands.toList()
        pendingCommands.clear()
        
        Log.d(TAG, "Processing ${commandsToProcess.size} pending commands")
        
        commandsToProcess.forEachIndexed { index, command ->
            handler.postDelayed({
                try {
                    command()
                } catch (e: Exception) {
                    Log.e(TAG, "Pending command execution failed", e)
                }
                lastCommandTime = System.currentTimeMillis()
            }, index * COMMAND_INTERVAL_MS)
        }
    }
    
    /**
     * Pause the queue - new commands will be queued but not executed
     */
    fun pause() {
        Log.d(TAG, "Command queue paused")
        isPaused = true
    }
    
    /**
     * Resume the queue and process any pending commands
     */
    fun resume() {
        Log.d(TAG, "Command queue resumed")
        isPaused = false
        if (isPostConnectionDelayComplete && pendingCommands.isNotEmpty()) {
            processPendingCommands()
        }
    }
    
    /**
     * Clear all pending commands and reset state
     */
    fun clear() {
        Log.d(TAG, "Command queue cleared")
        handler.removeCallbacksAndMessages(null)
        pendingCommands.clear()
        lastCommandTime = 0
        isPostConnectionDelayComplete = false
        isPaused = false
    }
    
    /**
     * Reset for new connection
     */
    fun reset() {
        clear()
    }
    
    /**
     * Check if queue is ready to accept commands
     */
    fun isReady(): Boolean {
        return isPostConnectionDelayComplete && !isPaused
    }
    
    /**
     * Get number of pending commands
     */
    fun getPendingCount(): Int {
        return pendingCommands.size
    }
}
