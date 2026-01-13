import admin from 'firebase-admin';

class ShardHelper {
  static getCurrentShardId() {
    const now = new Date();
    const year = now.getUTCFullYear();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const day = String(now.getUTCDate()).padStart(2, '0');
    const hour = now.getUTCHours() < 12 ? '00h' : '12h';
    
    return `${year}-${month}-${day}_${hour}`;
  }

  static getShardIdForDate(date) {
    const year = date.getUTCFullYear();
    const month = String(date.getUTCMonth() + 1).padStart(2, '0');
    const day = String(date.getUTCDate()).padStart(2, '0');
    const hour = date.getUTCHours() < 12 ? '00h' : '12h';
    
    return `${year}-${month}-${day}_${hour}`;
  }

  static generateBatchId() {
    return `batch_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  static hashCode(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash);
  }

  static getCurrentShardBatchesRef(db, userId = null) {
    const shardId = this.getCurrentShardId();
    const subShard = userId ? this.hashCode(userId) % 10 : Math.floor(Math.random() * 10);
    const fullShardId = `${shardId}_sub${subShard}`;
    
    return db
      .collection('click_analytics')
      .doc(fullShardId)
      .collection('batches');
  }

  static async getUnprocessedBatches(db, shardId, limit = 100) {
    const subShardPromises = [];
    
    for (let i = 0; i < 10; i++) {
      const fullShardId = `${shardId}_sub${i}`;
      
      const promise = db
        .collection('click_analytics')
        .doc(fullShardId)
        .collection('batches')
        .where('processed', '==', false)
        .orderBy('timestamp', 'asc')
        .limit(Math.ceil(limit / 10))
        .get();
      
      subShardPromises.push(promise);
    }

    const snapshots = await Promise.all(subShardPromises);
    const allDocs = [];
    
    for (const snapshot of snapshots) {
      allDocs.push(...snapshot.docs);
    }

    allDocs.sort((a, b) => {
      const aTime = a.data().timestamp?.toMillis() || 0;
      const bTime = b.data().timestamp?.toMillis() || 0;
      return aTime - bTime;
    });

    return allDocs.slice(0, limit);
  }

  static async markBatchesProcessed(db, batchDocs) {
    if (batchDocs.length === 0) return;

    // Group batches by their actual sub-shard (from document reference)
    const batchesBySubShard = new Map();
    
    for (const doc of batchDocs) {
      // Extract sub-shard ID from the document's parent path
      const subShardId = doc.ref.parent.parent.id;
      
      if (!batchesBySubShard.has(subShardId)) {
        batchesBySubShard.set(subShardId, []);
      }
      batchesBySubShard.get(subShardId).push(doc.id);
    }

    console.log(`Marking ${batchDocs.length} batches across ${batchesBySubShard.size} sub-shards`);

    // Update each sub-shard separately
    const updatePromises = [];
    
    for (const [subShardId, batchIds] of batchesBySubShard.entries()) {
      const chunks = this.chunkArray(batchIds, 500);
      
      for (const chunk of chunks) {
        const promise = (async () => {
          const batch = db.batch();
          
          for (const batchId of chunk) {
            const ref = db
              .collection('click_analytics')
              .doc(subShardId)
              .collection('batches')
              .doc(batchId);
            
            batch.update(ref, {
              processed: true,
              processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          
          await batch.commit();
        })();
        
        updatePromises.push(promise);
      }
    }

    // Execute all updates in parallel
    const results = await Promise.allSettled(updatePromises);
    
    const failures = results.filter((r) => r.status === 'rejected');
    if (failures.length > 0) {
      console.error(`Failed to mark ${failures.length} batch chunks:`, 
        failures.map((f) => f.reason));
    }
    const shardId = batchDocs[0].ref.parent.parent.id.split('_sub')[0];
    await db
      .collection('click_analytics')
      .doc(`${shardId}_metadata`)
      .update({
        pendingCount: admin.firestore.FieldValue.increment(-batchDocs.length),
      })
      .catch(() => {
        // Ignore if metadata doesn't exist
      });
  }

  static async markBatchesAsFailed(db, batchDocs, errorMessage = null) {
    if (batchDocs.length === 0) return;

    const batchesBySubShard = new Map();
    
    for (const doc of batchDocs) {
      const subShardId = doc.ref.parent.parent.id;
      
      if (!batchesBySubShard.has(subShardId)) {
        batchesBySubShard.set(subShardId, []);
      }
      batchesBySubShard.get(subShardId).push(doc.id);
    }

    const updatePromises = [];
    
    for (const [subShardId, batchIds] of batchesBySubShard.entries()) {
      const chunks = this.chunkArray(batchIds, 500);
      
      for (const chunk of chunks) {
        const promise = (async () => {
          const batch = db.batch();
          
          for (const batchId of chunk) {
            const ref = db
              .collection('click_analytics')
              .doc(subShardId)
              .collection('batches')
              .doc(batchId);
            
            const updateData = {
              processed: true,
              failed: true,
              failedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            
            if (errorMessage) {
              updateData.errorMessage = errorMessage.substring(0, 500);
            }
            
            batch.update(ref, updateData);
          }
          
          await batch.commit();
        })();
        
        updatePromises.push(promise);
      }
    }

    await Promise.allSettled(updatePromises);
  }

  static async cleanupOldShards(db) {
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const cutoffShardId = this.getShardIdForDate(sevenDaysAgo);
    
    const snapshot = await db
      .collection('click_analytics')
      .where(admin.firestore.FieldPath.documentId(), '<', cutoffShardId)
      .limit(50)
      .get();

    if (snapshot.empty) {
      console.log('✅ No old shards to cleanup');
      return;
    }

    console.log(`🧹 Cleaning up ${snapshot.size} old shard documents`);

    let deletedCount = 0;

    // Delete in parallel for better performance
    const deletePromises = snapshot.docs.map(async (doc) => {
      try {
        let hasMore = true;
        let totalBatchesDeleted = 0;

        while (hasMore) {
          const batchesSnapshot = await doc.ref
            .collection('batches')
            .limit(500)
            .get();
          
          if (batchesSnapshot.empty) {
            hasMore = false;
            break;
          }

          const chunks = this.chunkArray(batchesSnapshot.docs, 500);
          await Promise.all(chunks.map(async (chunk) => {
            const batch = db.batch();
            chunk.forEach((batchDoc) => batch.delete(batchDoc.ref));
            await batch.commit();
            totalBatchesDeleted += chunk.length;
          }));
        }

        await doc.ref.delete();
        deletedCount++;
        
        console.log(`✅ Deleted shard: ${doc.id} (${totalBatchesDeleted} batches)`);
      } catch (error) {
        console.error(`❌ Error deleting shard ${doc.id}: ${error.message}`);
      }
    });

    await Promise.allSettled(deletePromises);

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'shard_cleanup_completed',
      deleted: deletedCount,
    }));
  }

  static async getShardStats(db, shardId) {
    const stats = {
      totalBatches: 0,
      processedBatches: 0,
      failedBatches: 0,
      pendingBatches: 0,
      oldestPending: null,
      subShardBreakdown: [],
    };

    const subShardPromises = [];
    
    for (let i = 0; i < 10; i++) {
      const fullShardId = `${shardId}_sub${i}`;
      subShardPromises.push(
        db.collection('click_analytics')
          .doc(fullShardId)
          .collection('batches')
          .get(),
      );
    }

    const snapshots = await Promise.all(subShardPromises);

    snapshots.forEach((snapshot, i) => {
      let subShardProcessed = 0;
      let subShardFailed = 0;
      let subShardPending = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data();
        stats.totalBatches++;

        if (data.processed) {
          subShardProcessed++;
          stats.processedBatches++;
          if (data.failed) {
            subShardFailed++;
            stats.failedBatches++;
          }
        } else {
          subShardPending++;
          stats.pendingBatches++;
          
          const timestamp = data.timestamp?.toMillis() || Date.now();
          if (!stats.oldestPending || timestamp < stats.oldestPending) {
            stats.oldestPending = timestamp;
          }
        }
      }

      stats.subShardBreakdown.push({
        subShard: i,
        total: snapshot.size,
        processed: subShardProcessed,
        failed: subShardFailed,
        pending: subShardPending,
      });
    });

    return stats;
  }

  static async incrementBatchRetry(db, batchDoc) {
    try {
      await batchDoc.ref.update({
        retryCount: admin.firestore.FieldValue.increment(1),
        lastRetryAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error(`Error incrementing retry for ${batchDoc.id}: ${error.message}`);
    }
  }

  static chunkArray(array, size) {
    const chunks = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }
}

export {ShardHelper};
