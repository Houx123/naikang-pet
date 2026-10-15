#import <Cocoa/Cocoa.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

static NSString * const CodexExecutable = @"/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex";

@interface QPHistory : NSObject
@property NSMutableArray<NSDictionary *> *samples;
@property NSURL *fileURL;
- (void)appendSnapshot:(NSDictionary *)snapshot;
- (NSNumber *)rateForSnapshot:(NSDictionary *)snapshot primary:(BOOL)primary;
@end

@implementation QPHistory
- (instancetype)init {
    if ((self = [super init])) {
        NSURL *base = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        NSURL *dir = [base URLByAppendingPathComponent:@"QuotaPet" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        _fileURL = [dir URLByAppendingPathComponent:@"history.json"];
        NSData *data = [NSData dataWithContentsOfURL:_fileURL];
        NSArray *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        _samples = [saved isKindOfClass:NSArray.class] ? [saved mutableCopy] : [NSMutableArray array];
        NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - 8 * 24 * 3600;
        NSIndexSet *old = [_samples indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
            return [obj[@"timestamp"] doubleValue] < cutoff;
        }];
        [_samples removeObjectsAtIndexes:old];
    }
    return self;
}

- (void)appendSnapshot:(NSDictionary *)snapshot {
    NSDictionary *primary = snapshot[@"primary"];
    NSDictionary *secondary = snapshot[@"secondary"];
    NSDictionary *sample = @{
        @"timestamp": snapshot[@"capturedAt"],
        @"primaryUsed": primary[@"usedPercent"] ?: NSNull.null,
        @"primaryReset": primary[@"resetsAt"] ?: NSNull.null,
        @"secondaryUsed": secondary[@"usedPercent"] ?: NSNull.null,
        @"secondaryReset": secondary[@"resetsAt"] ?: NSNull.null
    };
    NSDictionary *last = self.samples.lastObject;
    if (last && [sample[@"timestamp"] doubleValue] - [last[@"timestamp"] doubleValue] < 30 &&
        [sample[@"primaryUsed"] isEqual:last[@"primaryUsed"]] &&
        [sample[@"secondaryUsed"] isEqual:last[@"secondaryUsed"]]) return;
    [self.samples addObject:sample];
    if (self.samples.count > 1200) {
        [self.samples removeObjectsInRange:NSMakeRange(0, self.samples.count - 1200)];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.samples options:0 error:nil];
    [data writeToURL:self.fileURL options:NSDataWritingAtomic error:nil];
}

- (NSNumber *)rateForSnapshot:(NSDictionary *)snapshot primary:(BOOL)primaryFlag {
    NSDictionary *window = snapshot[primaryFlag ? @"primary" : @"secondary"];
    NSNumber *usedNumber = window[@"usedPercent"];
    NSNumber *resetNumber = window[@"resetsAt"];
    if (!usedNumber || !resetNumber) return nil;
    NSInteger used = usedNumber.integerValue;
    NSTimeInterval now = [snapshot[@"capturedAt"] doubleValue];
    NSTimeInterval horizon = primaryFlag ? 3600 : 24 * 3600;
    NSString *usedKey = primaryFlag ? @"primaryUsed" : @"secondaryUsed";
    NSString *resetKey = primaryFlag ? @"primaryReset" : @"secondaryReset";
    for (NSDictionary *sample in self.samples) {
        id sampleUsed = sample[usedKey];
        id sampleReset = sample[resetKey];
        if (sampleUsed == NSNull.null || sampleReset == NSNull.null) continue;
        NSTimeInterval age = now - [sample[@"timestamp"] doubleValue];
        if (age < 0 || age > horizon || ![sampleReset isEqual:resetNumber] || [sampleUsed integerValue] > used) continue;
        double hours = age / 3600.0;
        if (hours < 0.03) return nil;
        return @(MAX(0, (used - [sampleUsed integerValue]) / hours));
    }
    return nil;
}
@end

@interface QPUsageClient : NSObject
@property (copy) void (^snapshotHandler)(NSDictionary *snapshot);
@property (copy) void (^statusHandler)(NSString *status);
@property NSTask *task;
@property NSFileHandle *input;
@property NSMutableData *buffer;
@property NSInteger requestID;
@property BOOL initialized;
@property NSTimer *timer;
- (void)start;
- (void)stop;
- (void)refresh;
@end

@implementation QPUsageClient
- (instancetype)init {
    if ((self = [super init])) {
        _buffer = [NSMutableData data];
        _requestID = 1;
    }
    return self;
}

- (void)start {
    [self stop];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:CodexExecutable]) {
        if (self.statusHandler) self.statusHandler(@"未找到 ChatGPT 的 Codex 组件");
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    NSPipe *stdinPipe = [NSPipe pipe];
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.executableURL = [NSURL fileURLWithPath:CodexExecutable];
    task.arguments = @[@"app-server", @"--stdio"];
    task.standardInput = stdinPipe;
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *ended) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || self.task != ended) return;
            self.initialized = NO;
            if (self.statusHandler) self.statusHandler(@"连接已断开，8 秒后重试…");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (weakSelf.task == ended) [weakSelf start];
            });
        });
    };
    stdoutPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (!data.length) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf consume:data]; });
    };
    stderrPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) { (void)handle.availableData; };
    NSError *error;
    if (![task launchAndReturnError:&error]) {
        if (self.statusHandler) self.statusHandler([NSString stringWithFormat:@"连接失败：%@", error.localizedDescription]);
        return;
    }
    self.task = task;
    self.input = stdinPipe.fileHandleForWriting;
    self.initialized = NO;
    if (self.statusHandler) self.statusHandler(@"正在连接额度服务…");
    [self send:@{
        @"id": @(self.requestID++),
        @"method": @"initialize",
        @"params": @{
            @"clientInfo": @{@"name": @"quota-pet", @"title": @"奶康", @"version": @"1.4.0"},
            @"capabilities": @{@"optOutNotificationMethods": @[@"remoteControl/status/changed"]}
        }
    }];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    self.task.terminationHandler = nil;
    [self.task terminate];
    self.task = nil;
    self.input = nil;
    self.initialized = NO;
    [self.buffer setLength:0];
}

- (void)refresh {
    if (!self.task.running) { [self start]; return; }
    if (!self.initialized) return;
    [self send:@{
        @"id": @(self.requestID++),
        @"method": @"account/rateLimits/read",
        @"params": @{@"excludeResetCreditDetails": @YES}
    }];
}

- (void)send:(NSDictionary *)object {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    NSMutableData *line = [json mutableCopy];
    uint8_t newline = '\n';
    [line appendBytes:&newline length:1];
    @try { [self.input writeData:line]; } @catch (__unused NSException *exception) { }
}

- (void)consume:(NSData *)data {
    [self.buffer appendData:data];
    NSData *newline = [NSData dataWithBytes:"\n" length:1];
    while (YES) {
        NSRange range = [self.buffer rangeOfData:newline options:0 range:NSMakeRange(0, self.buffer.length)];
        if (range.location == NSNotFound) break;
        NSData *line = [self.buffer subdataWithRange:NSMakeRange(0, range.location)];
        [self.buffer replaceBytesInRange:NSMakeRange(0, NSMaxRange(range)) withBytes:NULL length:0];
        NSDictionary *object = line.length ? [NSJSONSerialization JSONObjectWithData:line options:0 error:nil] : nil;
        if ([object isKindOfClass:NSDictionary.class]) [self handle:object];
    }
}

- (void)handle:(NSDictionary *)object {
    if (!self.initialized && object[@"id"] && object[@"result"]) {
        self.initialized = YES;
        [self send:@{@"method": @"initialized"}];
        [self refresh];
        __weak typeof(self) weakSelf = self;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:120 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf refresh]; }];
        return;
    }
    if ([object[@"method"] isEqual:@"account/rateLimits/updated"]) { [self refresh]; return; }
    NSDictionary *result = object[@"result"];
    NSDictionary *limits = [result isKindOfClass:NSDictionary.class] ? result[@"rateLimits"] : nil;
    if (![limits isKindOfClass:NSDictionary.class]) return;
    NSDictionary *snapshot = @{
        @"primary": [limits[@"primary"] isKindOfClass:NSDictionary.class] ? limits[@"primary"] : @{},
        @"secondary": [limits[@"secondary"] isKindOfClass:NSDictionary.class] ? limits[@"secondary"] : @{},
        @"planType": limits[@"planType"] ?: @"",
        @"ordinaryUsageAllowed": result[@"ordinaryUsageAllowed"] ?: NSNull.null,
        @"capturedAt": @(NSDate.date.timeIntervalSince1970)
    };
    if (self.snapshotHandler) self.snapshotHandler(snapshot);
}
@end

@interface QPNetworkMonitor : NSObject
@property (copy) void (^updateHandler)(NSString *localIP, NSString *publicIP, NSString *ipLocation, double downloadBps, double uploadBps);
@property NSTimer *trafficTimer;
@property NSTimer *publicIPTimer;
@property uint64_t lastInputBytes, lastOutputBytes;
@property NSTimeInterval lastSampleTime;
@property NSString *publicIP;
@property NSString *ipLocation;
- (void)start;
- (void)stop;
@end

@implementation QPNetworkMonitor
- (instancetype)init {
    if ((self = [super init])) {
        _publicIP = @"获取中…";
        _ipLocation = @"获取中…";
    }
    return self;
}

- (void)start {
    [self stop];
    [self sampleTraffic];
    __weak typeof(self) weakSelf = self;
    self.trafficTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf sampleTraffic]; }];
    [self refreshPublicIP];
    self.publicIPTimer = [NSTimer scheduledTimerWithTimeInterval:600 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf refreshPublicIP]; }];
}

- (void)stop {
    [self.trafficTimer invalidate];
    [self.publicIPTimer invalidate];
    self.trafficTimer = nil;
    self.publicIPTimer = nil;
}

- (NSDictionary *)networkSnapshot {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0 || !interfaces) return @{ @"localIP": @"不可用", @"input": @0, @"output": @0 };

    NSString *selectedName = nil;
    NSString *localIP = nil;
    NSInteger selectedPriority = NSIntegerMax;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET) continue;
        if (!(item->ifa_flags & IFF_UP) || (item->ifa_flags & IFF_LOOPBACK)) continue;
        char host[INET_ADDRSTRLEN] = {0};
        struct sockaddr_in *address = (struct sockaddr_in *)item->ifa_addr;
        if (!inet_ntop(AF_INET, &address->sin_addr, host, sizeof(host))) continue;
        NSString *ip = [NSString stringWithUTF8String:host];
        if ([ip hasPrefix:@"169.254."]) continue;
        NSString *name = [NSString stringWithUTF8String:item->ifa_name];
        NSInteger priority = [name isEqualToString:@"en0"] ? 0 : ([name isEqualToString:@"en1"] ? 1 : ([name isEqualToString:@"bridge0"] ? 2 : ([name isEqualToString:@"pdp_ip0"] ? 3 : ([name hasPrefix:@"utun"] ? 20 : 10))));
        if (priority < selectedPriority) {
            selectedPriority = priority;
            selectedName = name;
            localIP = ip;
        }
    }

    uint64_t inputBytes = 0, outputBytes = 0;
    if (selectedName) {
        for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
            if (!item->ifa_addr || item->ifa_addr->sa_family != AF_LINK || !item->ifa_data) continue;
            NSString *name = [NSString stringWithUTF8String:item->ifa_name];
            if (![name isEqualToString:selectedName]) continue;
            struct if_data *data = (struct if_data *)item->ifa_data;
            inputBytes = data->ifi_ibytes;
            outputBytes = data->ifi_obytes;
            break;
        }
    }
    freeifaddrs(interfaces);
    return @{ @"localIP": localIP ?: @"不可用", @"input": @(inputBytes), @"output": @(outputBytes) };
}

- (void)sampleTraffic {
    NSDictionary *snapshot = [self networkSnapshot];
    uint64_t inputBytes = [snapshot[@"input"] unsignedLongLongValue];
    uint64_t outputBytes = [snapshot[@"output"] unsignedLongLongValue];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    double download = 0, upload = 0;
    NSTimeInterval elapsed = now - self.lastSampleTime;
    if (self.lastSampleTime > 0 && elapsed > 0 && inputBytes >= self.lastInputBytes && outputBytes >= self.lastOutputBytes) {
        download = (inputBytes - self.lastInputBytes) / elapsed;
        upload = (outputBytes - self.lastOutputBytes) / elapsed;
    }
    self.lastInputBytes = inputBytes;
    self.lastOutputBytes = outputBytes;
    self.lastSampleTime = now;
    if (self.updateHandler) self.updateHandler(snapshot[@"localIP"], self.publicIP, self.ipLocation, download, upload);
}

- (void)refreshPublicIP {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 6;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURL *url = [NSURL URLWithString:@"https://ipwho.is/?lang=zh-CN&fields=ip,success,country,region,city"];
    __weak typeof(self) weakSelf = self;
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *address = nil;
        NSString *location = nil;
        if (!error && data.length) {
            NSDictionary *object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![object[@"success"] isEqual:@NO] && [object[@"ip"] isKindOfClass:NSString.class]) {
                address = object[@"ip"];
                NSMutableArray<NSString *> *parts = [NSMutableArray array];
                for (NSString *key in @[@"country", @"region", @"city"]) {
                    NSString *part = [object[key] isKindOfClass:NSString.class] ? object[key] : nil;
                    if (part.length && ![parts containsObject:part]) [parts addObject:part];
                }
                location = parts.count ? [parts componentsJoinedByString:@" · "] : @"未知";
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            self.publicIP = address ?: @"获取失败";
            self.ipLocation = location ?: @"获取失败";
            [self sampleTraffic];
        });
        [session finishTasksAndInvalidate];
    }] resume];
}
@end

@interface QPLocalSyncServer : NSObject
@property int serverSocket;
@property BOOL running;
@property NSString *pairingCode;
@property NSDictionary *payload;
- (void)start;
- (void)stop;
- (void)updatePayload:(NSDictionary *)payload;
@end

@implementation QPLocalSyncServer
- (instancetype)init {
    if ((self = [super init])) {
        _serverSocket = -1;
        NSURL *base = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        NSURL *dir = [base URLByAppendingPathComponent:@"QuotaPet" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *codeURL = [dir URLByAppendingPathComponent:@"pairing-code.txt"];
        NSString *saved = [NSString stringWithContentsOfURL:codeURL encoding:NSUTF8StringEncoding error:nil];
        saved = [saved stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (saved.length == 6) _pairingCode = saved;
        else {
            _pairingCode = [NSString stringWithFormat:@"%06u", arc4random_uniform(1000000)];
            [_pairingCode writeToURL:codeURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        _payload = @{
            @"petName": @"奶康", @"available": @NO, @"primaryRemaining": @0,
            @"secondaryRemaining": @0, @"primaryResetsAt": @0, @"burnRate": @0,
            @"publicIP": @"获取中…", @"ipLocation": @"获取中…", @"localIP": @"检测中…",
            @"downloadBps": @0, @"uploadBps": @0, @"updatedAt": @(NSDate.date.timeIntervalSince1970)
        };
    }
    return self;
}

- (void)start {
    if (self.running) return;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return;
    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(48765);
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 8) != 0) {
        close(fd);
        return;
    }
    self.serverSocket = fd;
    self.running = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (weakSelf.running) {
            int client = accept(fd, NULL, NULL);
            if (client < 0) continue;
            [weakSelf handleClient:client];
            close(client);
        }
    });
}

- (void)stop {
    self.running = NO;
    if (self.serverSocket >= 0) {
        shutdown(self.serverSocket, SHUT_RDWR);
        close(self.serverSocket);
        self.serverSocket = -1;
    }
}

- (void)updatePayload:(NSDictionary *)payload {
    @synchronized (self) { self.payload = [payload copy]; }
}

- (void)handleClient:(int)client {
    char buffer[4096] = {0};
    ssize_t count = recv(client, buffer, sizeof(buffer) - 1, 0);
    if (count <= 0) return;
    NSString *request = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)count encoding:NSUTF8StringEncoding] ?: @"";
    NSString *expected = [NSString stringWithFormat:@"GET /status?code=%@ ", self.pairingCode];
    BOOL authorized = [request hasPrefix:expected];
    NSDictionary *bodyObject;
    NSInteger status;
    NSString *statusText;
    if (authorized) {
        @synchronized (self) { bodyObject = self.payload; }
        status = 200;
        statusText = @"OK";
    } else {
        bodyObject = @{ @"error": @"配对码不正确" };
        status = 401;
        statusText = @"Unauthorized";
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:bodyObject options:0 error:nil] ?: [NSData data];
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %lu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n", status, statusText, (unsigned long)body.length];
    NSData *headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
    send(client, headerData.bytes, headerData.length, 0);
    send(client, body.bytes, body.length, 0);
}

- (void)dealloc { [self stop]; }
@end

@interface QPMeterBar : NSView
@property (nonatomic) double value;
@property (nonatomic) NSColor *fillColor;
@end

@implementation QPMeterBar
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) _fillColor = NSColor.systemGreenColor;
    return self;
}
- (void)setValue:(double)value { _value = value; self.needsDisplay = YES; }
- (void)setFillColor:(NSColor *)fillColor { _fillColor = fillColor; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.bounds.size.height/2 yRadius:self.bounds.size.height/2];
    [[NSColor.labelColor colorWithAlphaComponent:0.12] setFill];
    [track fill];
    CGFloat width = self.bounds.size.width * MIN(1, MAX(0, self.value / 100.0));
    if (width > 0) {
        NSRect rect = NSMakeRect(0, 0, MAX(self.bounds.size.height, width), self.bounds.size.height);
        NSBezierPath *fill = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:rect.size.height/2 yRadius:rect.size.height/2];
        [self.fillColor setFill];
        [fill fill];
    }
}
@end

@interface QPDashboard : NSObject
@property NSPanel *panel;
@property NSTextField *primaryLabel, *primaryValue, *secondaryLabel, *secondaryValue, *speedLabel, *resetLabel, *updateLabel;
@property NSTextField *publicIPLabel, *ipLocationLabel, *localIPLabel, *trafficLabel;
@property QPMeterBar *primaryBar, *secondaryBar;
@property QPUsageClient *client;
@property QPNetworkMonitor *networkMonitor;
@property QPLocalSyncServer *syncServer;
@property QPHistory *history;
@property NSDictionary *latestUsageSnapshot;
@property NSString *latestLocalIP, *latestPublicIP, *latestIPLocation;
@property double latestDownloadBps, latestUploadBps, latestBurnRate;
@property (copy) void (^snapshotHandler)(NSDictionary *snapshot);
- (void)show;
- (void)toggle;
- (void)refresh;
@end

@implementation QPDashboard
- (instancetype)init {
    if ((self = [super init])) {
        _history = [[QPHistory alloc] init];
        _client = [[QPUsageClient alloc] init];
        _networkMonitor = [[QPNetworkMonitor alloc] init];
        _syncServer = [[QPLocalSyncServer alloc] init];
        [_syncServer start];
        [self buildPanel];
        __weak typeof(self) weakSelf = self;
        _client.snapshotHandler = ^(NSDictionary *snapshot) { [weakSelf applySnapshot:snapshot]; };
        _client.statusHandler = ^(NSString *status) { weakSelf.resetLabel.stringValue = status; };
        _networkMonitor.updateHandler = ^(NSString *localIP, NSString *publicIP, NSString *ipLocation, double downloadBps, double uploadBps) {
            weakSelf.latestLocalIP = localIP;
            weakSelf.latestPublicIP = publicIP;
            weakSelf.latestIPLocation = ipLocation;
            weakSelf.latestDownloadBps = downloadBps;
            weakSelf.latestUploadBps = uploadBps;
            weakSelf.publicIPLabel.stringValue = [NSString stringWithFormat:@"公网 IP  %@", publicIP];
            weakSelf.ipLocationLabel.stringValue = [NSString stringWithFormat:@"IP 归属地  %@", ipLocation];
            weakSelf.localIPLabel.stringValue = [NSString stringWithFormat:@"局域网  %@  ·  配对 %@", localIP, weakSelf.syncServer.pairingCode];
            weakSelf.trafficLabel.stringValue = [NSString stringWithFormat:@"↓ %@    ↑ %@", [weakSelf formatBytesPerSecond:downloadBps], [weakSelf formatBytesPerSecond:uploadBps]];
            [weakSelf publishSyncPayload];
        };
        [_client start];
        [_networkMonitor start];
    }
    return self;
}
- (void)dealloc { [self.client stop]; [self.networkMonitor stop]; [self.syncServer stop]; }

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    return label;
}

- (void)buildPanel {
    self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,330,272) styleMask:(NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel) backing:NSBackingStoreBuffered defer:NO];
    self.panel.level = NSFloatingWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.movableByWindowBackground = YES;
    self.panel.hidesOnDeactivate = NO;
    NSRect visible = NSScreen.mainScreen.visibleFrame;
    [self.panel setFrameOrigin:NSMakePoint(NSMaxX(visible)-352, NSMaxY(visible)-350)];

    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:self.panel.contentView.bounds];
    effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    effect.material = NSVisualEffectMaterialHUDWindow;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = 18;
    effect.layer.masksToBounds = YES;
    [self.panel.contentView addSubview:effect];

    [effect addSubview:[self label:@"奶康 · 状态" frame:NSMakeRect(18,240,220,22) size:15 weight:NSFontWeightSemibold]];
    NSButton *refresh = [NSButton buttonWithTitle:@"↻" target:self action:@selector(refreshPressed:)];
    refresh.frame = NSMakeRect(284,238,28,26); refresh.bordered = NO; refresh.font = [NSFont systemFontOfSize:18 weight:NSFontWeightMedium]; refresh.toolTip = @"立即刷新";
    [effect addSubview:refresh];

    self.primaryLabel = [self label:@"5 小时额度" frame:NSMakeRect(18,217,110,17) size:12 weight:NSFontWeightMedium];
    self.primaryValue = [self label:@"连接中…" frame:NSMakeRect(174,217,138,17) size:12 weight:NSFontWeightSemibold]; self.primaryValue.alignment = NSTextAlignmentRight;
    self.primaryBar = [[QPMeterBar alloc] initWithFrame:NSMakeRect(18,205,294,8)];
    self.secondaryLabel = [self label:@"7 天额度" frame:NSMakeRect(18,180,110,17) size:12 weight:NSFontWeightMedium];
    self.secondaryValue = [self label:@"—" frame:NSMakeRect(174,180,138,17) size:12 weight:NSFontWeightSemibold]; self.secondaryValue.alignment = NSTextAlignmentRight;
    self.secondaryBar = [[QPMeterBar alloc] initWithFrame:NSMakeRect(18,168,294,8)];
    for (NSView *view in @[self.primaryLabel,self.primaryValue,self.primaryBar,self.secondaryLabel,self.secondaryValue,self.secondaryBar]) [effect addSubview:view];

    self.speedLabel = [self label:@"消耗速度：等待采样" frame:NSMakeRect(18,132,294,18) size:12 weight:NSFontWeightMedium];
    self.speedLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    self.resetLabel = [self label:@"正在读取额度…" frame:NSMakeRect(18,113,230,16) size:11 weight:NSFontWeightRegular]; self.resetLabel.textColor = NSColor.secondaryLabelColor;
    self.updateLabel = [self label:@"" frame:NSMakeRect(250,113,62,16) size:10 weight:NSFontWeightRegular]; self.updateLabel.alignment = NSTextAlignmentRight; self.updateLabel.textColor = NSColor.tertiaryLabelColor;
    [effect addSubview:self.speedLabel]; [effect addSubview:self.resetLabel]; [effect addSubview:self.updateLabel];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(18,103,294,1)]; divider.boxType = NSBoxSeparator; [effect addSubview:divider];
    self.publicIPLabel = [self label:@"公网 IP  获取中…" frame:NSMakeRect(18,80,294,17) size:11 weight:NSFontWeightMedium];
    self.ipLocationLabel = [self label:@"IP 归属地  获取中…" frame:NSMakeRect(18,60,294,17) size:11 weight:NSFontWeightRegular];
    self.localIPLabel = [self label:@"局域网  检测中…" frame:NSMakeRect(18,40,294,17) size:11 weight:NSFontWeightRegular];
    self.trafficLabel = [self label:@"↓ 0 B/s    ↑ 0 B/s" frame:NSMakeRect(18,17,294,18) size:12 weight:NSFontWeightSemibold];
    self.publicIPLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
    self.ipLocationLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    self.localIPLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.trafficLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold];
    [effect addSubview:self.publicIPLabel]; [effect addSubview:self.ipLocationLabel]; [effect addSubview:self.localIPLabel]; [effect addSubview:self.trafficLabel];
}

- (void)show { [self.panel orderFrontRegardless]; }
- (void)toggle { self.panel.visible ? [self.panel orderOut:nil] : [self show]; }
- (void)refresh { self.resetLabel.stringValue = @"正在刷新…"; [self.client refresh]; }
- (void)refreshPressed:(id)sender { [self refresh]; }

- (NSString *)formatBytesPerSecond:(double)value {
    if (value < 1024) return [NSString stringWithFormat:@"%.0f B/s", value];
    if (value < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB/s", value / 1024];
    if (value < 1024 * 1024 * 1024) return [NSString stringWithFormat:@"%.2f MB/s", value / (1024 * 1024)];
    return [NSString stringWithFormat:@"%.2f GB/s", value / (1024 * 1024 * 1024)];
}

- (void)applySnapshot:(NSDictionary *)snapshot {
    self.latestUsageSnapshot = snapshot;
    [self.history appendSnapshot:snapshot];
    [self updateWindow:snapshot[@"primary"] label:self.primaryLabel value:self.primaryValue bar:self.primaryBar fallback:@"5 小时额度"];
    [self updateWindow:snapshot[@"secondary"] label:self.secondaryLabel value:self.secondaryValue bar:self.secondaryBar fallback:@"7 天额度"];
    NSNumber *rate = [self.history rateForSnapshot:snapshot primary:YES];
    if (rate.doubleValue > 0.01) self.speedLabel.stringValue = [NSString stringWithFormat:@"近 1 小时消耗  %.1f%% / 小时", rate.doubleValue];
    else {
        rate = [self.history rateForSnapshot:snapshot primary:NO];
        self.speedLabel.stringValue = rate.doubleValue > 0.01 ? [NSString stringWithFormat:@"近 24 小时消耗  %.2f%% / 小时", rate.doubleValue] : @"消耗速度：采样中（用量变化后显示）";
    }
    self.latestBurnRate = rate.doubleValue;
    if ([snapshot[@"ordinaryUsageAllowed"] isEqual:@NO]) self.resetLabel.stringValue = @"当前普通额度不可用";
    else {
        NSNumber *reset = snapshot[@"primary"][@"resetsAt"];
        self.resetLabel.stringValue = reset ? [NSString stringWithFormat:@"5 小时额度将在 %@ 后重置", [self countdown:reset.doubleValue]] : @"额度可用";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init]; formatter.dateFormat = @"HH:mm";
    self.updateLabel.stringValue = [formatter stringFromDate:NSDate.date];
    [self publishSyncPayload];
    if (self.snapshotHandler) self.snapshotHandler(snapshot);
}

- (void)publishSyncPayload {
    NSDictionary *primary = self.latestUsageSnapshot[@"primary"];
    NSDictionary *secondary = self.latestUsageSnapshot[@"secondary"];
    NSNumber *primaryUsed = primary[@"usedPercent"];
    NSNumber *secondaryUsed = secondary[@"usedPercent"];
    NSDictionary *payload = @{
        @"petName": @"奶康",
        @"available": @(primaryUsed != nil),
        @"primaryRemaining": primaryUsed ? @(MAX(0, 100 - primaryUsed.integerValue)) : @0,
        @"secondaryRemaining": secondaryUsed ? @(MAX(0, 100 - secondaryUsed.integerValue)) : @0,
        @"primaryResetsAt": primary[@"resetsAt"] ?: @0,
        @"burnRate": @(self.latestBurnRate),
        @"publicIP": self.latestPublicIP ?: @"获取中…",
        @"ipLocation": self.latestIPLocation ?: @"获取中…",
        @"localIP": self.latestLocalIP ?: @"检测中…",
        @"downloadBps": @(self.latestDownloadBps),
        @"uploadBps": @(self.latestUploadBps),
        @"updatedAt": @(NSDate.date.timeIntervalSince1970)
    };
    [self.syncServer updatePayload:payload];
}

- (void)updateWindow:(NSDictionary *)window label:(NSTextField *)label value:(NSTextField *)value bar:(QPMeterBar *)bar fallback:(NSString *)fallback {
    NSNumber *used = window[@"usedPercent"];
    if (!used) { value.stringValue = @"不可用"; bar.value = 0; return; }
    NSNumber *duration = window[@"windowDurationMins"];
    if (duration) label.stringValue = duration.integerValue >= 1440 ? [NSString stringWithFormat:@"%ld 天额度", duration.integerValue/1440] : [NSString stringWithFormat:@"%ld 小时额度", duration.integerValue/60];
    else label.stringValue = fallback;
    NSInteger remaining = MAX(0, MIN(100, 100-used.integerValue));
    value.stringValue = [NSString stringWithFormat:@"剩余 %ld%%", remaining];
    bar.value = remaining;
    bar.fillColor = remaining > 50 ? NSColor.systemGreenColor : (remaining > 20 ? NSColor.systemOrangeColor : NSColor.systemRedColor);
}

- (NSString *)countdown:(NSTimeInterval)timestamp {
    NSInteger seconds = MAX(0, timestamp - NSDate.date.timeIntervalSince1970);
    NSInteger hours = seconds / 3600, minutes = (seconds % 3600) / 60;
    return hours > 0 ? [NSString stringWithFormat:@"%ld小时%ld分", hours, minutes] : [NSString stringWithFormat:@"%ld分钟", minutes];
}
@end

@interface QPAppDelegate : NSObject <NSApplicationDelegate>
@property QPDashboard *dashboard;
@property NSStatusItem *statusItem;
@end

@implementation QPAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSImage *petIcon = [[NSImage alloc] initWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"StatusIcon" withExtension:@"png"]];
    petIcon.size = NSMakeSize(20, 20);
    petIcon.template = NO;
    self.statusItem.button.image = petIcon;
    self.statusItem.button.imagePosition = NSImageLeft;
    self.statusItem.button.title = @" --";
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"显示／隐藏奶康" action:@selector(togglePanel:) keyEquivalent:@""];
    [menu addItemWithTitle:@"立即刷新" action:@selector(refresh:) keyEquivalent:@"r"];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"退出奶康" action:@selector(quit:) keyEquivalent:@"q"];
    for (NSMenuItem *item in menu.itemArray) item.target = self;
    self.statusItem.menu = menu;
    self.dashboard = [[QPDashboard alloc] init];
    __weak typeof(self) weakSelf = self;
    self.dashboard.snapshotHandler = ^(NSDictionary *snapshot) {
        NSNumber *used = snapshot[@"primary"][@"usedPercent"];
        weakSelf.statusItem.button.title = [NSString stringWithFormat:@" %ld%%", MAX(0, 100-used.integerValue)];
    };
    [self.dashboard show];
}
- (void)togglePanel:(id)sender { [self.dashboard toggle]; }
- (void)refresh:(id)sender { [self.dashboard refresh]; }
- (void)quit:(id)sender { [NSApp terminate:nil]; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        QPAppDelegate *delegate = [[QPAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
