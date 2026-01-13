class DistributedRateLimiter {
    constructor() {
      // userId -> { count, windowStart }
      this.userRequests = new Map();
      
      // Cleanup interval (every 5 minutes)
      this.cleanupInterval = null;
      this.startCleanup();
    }
 
    async consume(userId, maxRequests, windowMs) {
      const now = Date.now();
      const userData = this.userRequests.get(userId);
  
      if (!userData) {
        // First request from this user
        this.userRequests.set(userId, {
          count: 1,
          windowStart: now,
        });
        return true;
      }
  
      // Check if window has expired
      const timeSinceWindowStart = now - userData.windowStart;
      
      if (timeSinceWindowStart > windowMs) {
        // Window expired - reset
        this.userRequests.set(userId, {
          count: 1,
          windowStart: now,
        });
        return true;
      }
  
      // Window still active - check count
      if (userData.count >= maxRequests) {
        // Rate limit exceeded
        console.warn(JSON.stringify({
          level: 'WARN',
          event: 'rate_limit_exceeded',
          userId,
          count: userData.count,
          maxRequests,
          windowMs,
        }));
        return false;
      }
  
      // Increment count
      userData.count++;
      this.userRequests.set(userId, userData);
      return true;
    }
  
    startCleanup() {
      if (this.cleanupInterval) return;
  
      // Run cleanup every 5 minutes
      this.cleanupInterval = setInterval(() => {
        this.cleanup();
      }, 5 * 60 * 1000);
    }

    stopCleanup() {
      if (this.cleanupInterval) {
        clearInterval(this.cleanupInterval);
        this.cleanupInterval = null;
      }
    }

    async cleanup() {
      const now = Date.now();
      const expiryMs = 10 * 60 * 1000; // 10 minutes
      let removedCount = 0;
  
      for (const [userId, userData] of this.userRequests.entries()) {
        const age = now - userData.windowStart;
        if (age > expiryMs) {
          this.userRequests.delete(userId);
          removedCount++;
        }
      }
  
      if (removedCount > 0) {
        console.log(JSON.stringify({
          level: 'INFO',
          event: 'rate_limiter_cleanup',
          removedEntries: removedCount,
          remainingEntries: this.userRequests.size,
        }));
      }
    }
 
    getStats() {
      return {
        totalUsers: this.userRequests.size,
        entries: Array.from(this.userRequests.entries()).map(([userId, data]) => ({
          userId,
          count: data.count,
          ageSeconds: Math.floor((Date.now() - data.windowStart) / 1000),
        })),
      };
    }
  
    clear() {
      this.userRequests.clear();
    }
  }
  
  export {DistributedRateLimiter};
