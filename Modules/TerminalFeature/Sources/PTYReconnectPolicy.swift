import Foundation

/// Policy for managing reconnection attempts with exponential backoff and jitter.
///
/// This policy implements a capped exponential backoff algorithm with optional
/// jitter to prevent thundering herd problems when multiple clients reconnect
/// simultaneously.
///
/// The backoff formula is:
/// ```
/// delay = min(baseDelay * multiplier^attempt, maxDelay)
/// delay = delay * (1 + random(-jitter, +jitter))
/// ```
public struct PTYReconnectPolicy: Sendable {
    /// Base delay in seconds for the first reconnection attempt.
    public let baseDelay: TimeInterval
    
    /// Maximum delay in seconds between reconnection attempts.
    public let maxDelay: TimeInterval
    
    /// Multiplier applied to the delay for each subsequent attempt.
    public let multiplier: Double
    
    /// Jitter factor (0.0 to 1.0) to add randomness to delays.
    /// A value of 0.3 means delays can vary by ±30%.
    public let jitter: Double
    
    /// Current attempt number (0-based).
    private var attempt: Int
    
    /// Creates a new reconnect policy.
    ///
    /// - Parameters:
    ///   - baseDelay: Base delay in seconds. Default is 1.0.
    ///   - maxDelay: Maximum delay in seconds. Default is 30.0.
    ///   - multiplier: Multiplier for exponential backoff. Default is 2.0.
    ///   - jitter: Jitter factor (0.0 to 1.0). Default is 0.3.
    public init(
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        multiplier: Double = 2.0,
        jitter: Double = 0.3
    ) {
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(baseDelay, maxDelay)
        self.multiplier = max(1.0, multiplier)
        self.jitter = min(1.0, max(0.0, jitter))
        self.attempt = 0
    }
    
    /// Returns the delay for the next reconnection attempt and increments the attempt counter.
    ///
    /// - Returns: The delay in seconds before the next reconnection attempt.
    public mutating func nextDelay() -> TimeInterval {
        let delay = calculateDelay(for: attempt)
        attempt += 1
        return delay
    }
    
    /// Resets the attempt counter to zero.
    ///
    /// Call this after a successful connection to reset the backoff.
    public mutating func reset() {
        attempt = 0
    }
    
    /// Returns the current attempt number.
    public var currentAttempt: Int {
        attempt
    }
    
    /// Calculates the delay for a given attempt number.
    private func calculateDelay(for attempt: Int) -> TimeInterval {
        // Calculate exponential backoff
        let exponentialDelay = baseDelay * pow(multiplier, Double(attempt))
        
        // Cap at maximum delay
        let cappedDelay = min(exponentialDelay, maxDelay)
        
        // Apply jitter if configured
        guard jitter > 0 else {
            return cappedDelay
        }
        
        // Generate random jitter in range [-jitter, +jitter]
        let jitterRange = jitter * 2
        let jitterOffset = (Double.random(in: 0..<1) * jitterRange) - jitter
        
        // Apply jitter and ensure non-negative result
        let jitteredDelay = cappedDelay * (1 + jitterOffset)
        return max(0, jitteredDelay)
    }
}
