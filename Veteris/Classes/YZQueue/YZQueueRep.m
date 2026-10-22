#import "YZQueueRep.h"
#import "YZQueueOps.h"
#import "YZDownloadResumeStore.h"
#import "../VAPIHelper/VAPIHelper.h"

@implementation YZQueueRep {
    YZApplication *_app;
    NSString *_resumeSourceURL;
    NSString *_resumeTargetPath;
}

static unsigned long long YZQueueFileSizeAtPath(NSString *path) {
    if ([path length] == 0) {
        return 0;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    return attrs != nil ? [attrs fileSize] : 0;
}

static unsigned long long YZQueueParallelPartBytesForPath(NSString *targetPath) {
    NSString *directory = [targetPath stringByDeletingLastPathComponent];
    NSString *prefix = [[targetPath lastPathComponent] stringByAppendingString:@".part."];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    unsigned long long bytes = 0;
    for (NSString *entry in contents) {
        if (![entry hasPrefix:prefix]) {
            continue;
        }
        NSString *suffix = [entry substringFromIndex:[prefix length]];
        if ([suffix length] == 0 || [suffix rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) {
            continue;
        }
        bytes += YZQueueFileSizeAtPath([directory stringByAppendingPathComponent:entry]);
    }
    return bytes;
}

static NSString *YZQueueStateLogName(YZRepState state) {
    switch (state) {
        case YZRepStateInstalled: return @"installed";
        case YZRepStateInstalling: return @"installing";
        case YZRepStateDownloaded: return @"downloaded";
        case YZRepStateDownloading: return @"downloading";
        case YZRepStateQueued: return @"queued";
        case YZRepStateFailed: return @"failed";
        case YZRepStatePaused: return @"paused";
        case YZRepStateCancelled: return @"cancelled";
    }
    return @"unknown";
}

static void YZAppendQueueOperationLog(YZQueueRep *rep, YZRepState state) {
    NSString *directory = downloadPath();
    if ([directory length] == 0) {
        return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        debugLog(@"Could not create download log directory %@: %@", directory, [error localizedDescription]);
        return;
    }

    NSString *logPath = [directory stringByAppendingPathComponent:@"VeterisDownload.log"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
    NSString *line = [NSString stringWithFormat:@"%@ event=%@ name=%@ bundle=%@ version=%@ mode=%@ path=%@\n",
                      [formatter stringFromDate:[NSDate date]],
                      YZQueueStateLogName(state),
                      rep.name ?: @"",
                      rep.bundleID ?: @"",
                      rep.version ?: @"",
                      rep.installAfterDownload ? @"install" : @"download-only",
                      rep.path ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized ([YZQueueRep class]) {
        if (![manager fileExistsAtPath:logPath]) {
            [manager createFileAtPath:logPath contents:nil attributes:nil];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (handle == nil) {
            return;
        }
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
            [handle synchronizeFile];
        } @catch (NSException *exception) {
            debugLog(@"Could not append download log: %@", [exception reason]);
        } @finally {
            [handle closeFile];
        }
    }
}

+ (void)detachRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url {
    [self detachRepWithYZApp:yzApp andURL:url trackDownloadStart:YES];
}

+ (void)detachRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url trackDownloadStart:(BOOL)trackDownloadStart {
    YZQueueRep *rep = [[YZQueueRep alloc] init];
    rep->_app = yzApp;
    rep->_invalid = NO;
    rep->_installAfterDownload = YES;
    rep->_resumeSourceURL = [url copy];
    rep->_resumeTargetPath = [downloadPathFor(yzApp.bundleID) copy];
    [rep refreshStoredDownloadProgress];
    __typeof__(rep) weakSelf = rep;
    rep->_downloadSelf = ^{
        [weakSelf setState:YZRepStateDownloading];
        if (trackDownloadStart) {
            [VAPIHelper trackDownloadStartForApplication:yzApp url:url downloadOnly:NO];
        }
        [YZQueueOps downloadFileToPath:url pathFromString:yzApp.bundleID parent:weakSelf];
    };
    if (url != nil) {
        rep->_app.path = url;
        [YZDownloadResumeStore upsertRecordForApplication:yzApp sourceURL:url targetPath:rep->_resumeTargetPath installAfterDownload:YES];
        [rep setState:YZRepStateQueued];
    } else {
        [rep setState:YZRepStateDownloaded];
    }
}

+ (void)detachPausedRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath {
    YZQueueRep *rep = [[YZQueueRep alloc] init];
    rep->_app = yzApp;
    rep->_invalid = NO;
    rep->_installAfterDownload = YES;
    rep->_resumeSourceURL = [url copy];
    rep->_resumeTargetPath = [targetPath copy];
    [rep refreshStoredDownloadProgress];
    __typeof__(rep) weakSelf = rep;
    rep->_downloadSelf = ^{
        [weakSelf setState:YZRepStateDownloading];
        [YZQueueOps downloadFileToPath:url pathFromString:yzApp.bundleID parent:weakSelf];
    };
    rep->_app.path = targetPath;
    [rep setState:YZRepStatePaused];
}

+ (void)detachDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath {
    [self detachDownloadOnlyRepWithYZApp:yzApp andURL:url targetPath:targetPath trackDownloadStart:YES];
}

+ (void)detachDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath trackDownloadStart:(BOOL)trackDownloadStart {
    YZQueueRep *rep = [[YZQueueRep alloc] init];
    rep->_app = yzApp;
    rep->_invalid = NO;
    rep->_installAfterDownload = NO;
    rep->_resumeSourceURL = [url copy];
    rep->_resumeTargetPath = [targetPath copy];
    [rep refreshStoredDownloadProgress];
    __typeof__(rep) weakSelf = rep;
    rep->_downloadSelf = ^{
        [weakSelf setState:YZRepStateDownloading];
        if (trackDownloadStart) {
            [VAPIHelper trackDownloadStartForApplication:yzApp url:url downloadOnly:YES];
        }
        [YZQueueOps downloadFileToPath:url targetPath:targetPath parent:weakSelf];
    };
    rep->_app.path = targetPath;
    [YZDownloadResumeStore upsertRecordForApplication:yzApp sourceURL:url targetPath:targetPath installAfterDownload:NO];
    [rep setState:YZRepStateQueued];
}

+ (void)detachPausedDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath {
    YZQueueRep *rep = [[YZQueueRep alloc] init];
    rep->_app = yzApp;
    rep->_invalid = NO;
    rep->_installAfterDownload = NO;
    rep->_resumeSourceURL = [url copy];
    rep->_resumeTargetPath = [targetPath copy];
    [rep refreshStoredDownloadProgress];
    __typeof__(rep) weakSelf = rep;
    rep->_downloadSelf = ^{
        [weakSelf setState:YZRepStateDownloading];
        [YZQueueOps downloadFileToPath:url targetPath:targetPath parent:weakSelf];
    };
    rep->_app.path = targetPath;
    [rep setState:YZRepStatePaused];
}

- (void)setState:(YZRepState)state {
    _state = state;
    YZAppendQueueOperationLog(self, state);
    if (_resumeSourceURL != nil && _resumeTargetPath != nil) {
        BOOL keepResumeRecord = (state == YZRepStateQueued ||
                                 state == YZRepStateDownloading ||
                                 state == YZRepStatePaused ||
                                 (self.installAfterDownload && (state == YZRepStateDownloaded || state == YZRepStateInstalling)));
        if (keepResumeRecord) {
            [YZDownloadResumeStore upsertRecordForApplication:_app
                                                    sourceURL:_resumeSourceURL
                                                   targetPath:_resumeTargetPath
                                         installAfterDownload:self.installAfterDownload];
        } else {
            [YZDownloadResumeStore removeRecordForTargetPath:_resumeTargetPath];
        }
    }
    [YZQueueOps notifyAppState:self];
}

- (void)refreshStoredDownloadProgress {
    NSString *targetPath = _resumeTargetPath ?: _app.path;
    unsigned long long current = YZQueueFileSizeAtPath(targetPath) + YZQueueParallelPartBytesForPath(targetPath);
    unsigned long long total = _app.sizeBytes;
    if (total > 0 && current > total) {
        current = total;
    }
    self.storedProgressCurrent = (NSUInteger)MIN(current, (unsigned long long)NSUIntegerMax);
    self.storedProgressTotal = (NSUInteger)MIN(total, (unsigned long long)NSUIntegerMax);
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return true;
    }
    if (![object isKindOfClass:[YZQueueRep class]]) {
        return false;
    }
    YZQueueRep *rep = (YZQueueRep *)object;
    return [rep.bundleID isEqualToString:self.bundleID] && [rep.version isEqualToString:self.version];
}

- (NSUInteger)hash {
    return [self.bundleID hash] ^ [self.version hash];
}

- (UIImage *)icon {
    return _app.icon;
}

- (NSString *)iconurl {
    return _app.iconurl;
}

- (NSString *)fallbackIconurl {
    return _app.fallback_iconurl;
}

- (NSString *)name {
    return _app.name;
}

- (NSString *)description {
    return _app.description;
}

- (NSString *)version {
    return _app.version;
}

- (NSString *)bundleID {
    return _app.bundleID;
}

- (NSString *)developer {
    return _app.developer;
}

- (NSString *)minimumOS {
    return _app.minimumOS;
}

- (NSString *)url {
    return _app.url;
}

- (NSString *)path {
    return _app.path;
}

- (void)setPath:(NSString *)path {
    _app.path = path;
}

@end
