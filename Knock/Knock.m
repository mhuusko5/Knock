#import <libactivator/libactivator.h>
#import <notify.h>
#import <CoreMotion/CoreMotion.h>
#include "IOHIDEventSystem.h"
#include "IOHIDEventSystemClient.h"
#import "KEvent.h"

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);

static float KFilteringFactor = 0.25;
static float KMinimumSideDelta = 1.1;
static float KMinimumFrontDelta = 0.9;
static float KAccelUpdateInterval = 0.01;
static NSString *KEventNameSide = @"com.mhuusko5.Knock.side";
static NSString *KEventNameFront = @"com.mhuusko5.Knock.front";

@interface Knock : NSObject

@property CMMotionManager *motionManager;
@property NSTimer *accelCheckTimer;
@property float currentAccelX, currentAccelY, currentAccelZ;
@property int screenStateToken;
@property NSDate *lastScreenActivity;
@property NSMutableArray *possibleEvents;
@property NSDate *lastEventPick;

@end

@implementation Knock

- (void)checkAcceleration {
    if (-[self.lastScreenActivity timeIntervalSinceNow] < 0.5) {
        return;
    }

    CMAcceleration acceleration = self.motionManager.accelerometerData.acceleration;
    float prevAccelX = self.currentAccelX;
    float prevAccelY = self.currentAccelY;
    float prevAccelZ = self.currentAccelZ;
    self.currentAccelX = acceleration.x - ((acceleration.x * KFilteringFactor) + (prevAccelX * (1.0 - KFilteringFactor)));
    self.currentAccelY = acceleration.y - ((acceleration.y * KFilteringFactor) + (prevAccelY * (1.0 - KFilteringFactor)));
    self.currentAccelZ = acceleration.z - ((acceleration.z * KFilteringFactor) + (prevAccelZ * (1.0 - KFilteringFactor)));

    if (-[self.lastEventPick timeIntervalSinceNow] < 0.33) {
        return;
    }

    if (self.possibleEvents.count > 0) {
        NSArray *sortedEvents = [self.possibleEvents sortedArrayUsingComparator: ^NSComparisonResult (KEvent *event1, KEvent *event2) {
            return [@(event2.score)compare : @(event1.score)];
        }];

        for (int i = 0; i < sortedEvents.count; i++) {
            NSLog(@"%@ %f", [sortedEvents[i] name], [sortedEvents[i] score]);
        }

        [LASharedActivator sendEventToListener:[LAEvent eventWithName:[sortedEvents[0] name] mode:[LASharedActivator currentEventMode]]];

        self.possibleEvents = [NSMutableArray array];
        self.lastEventPick = [NSDate date];

        return;
    }

    float deltaX = ABS(self.currentAccelX - prevAccelX);
    float deltaY = ABS(self.currentAccelY - prevAccelY);
    float deltaZ = ABS(self.currentAccelZ - prevAccelZ);

    if (deltaX > KMinimumSideDelta) {
        [self.possibleEvents addObject:[[KEvent alloc] initWithName:KEventNameSide score:deltaX / KMinimumSideDelta]];
    }

    if (deltaZ > KMinimumFrontDelta) {
        [self.possibleEvents addObject:[[KEvent alloc] initWithName:KEventNameFront score:deltaZ / KMinimumFrontDelta]];
    }
}

void handleSystemHIDEvent(void *target, void *refcon, IOHIDEventQueueRef queue, IOHIDEventRef event) {
	if (IOHIDEventGetType(event) == kIOHIDEventTypeDigitizer) {
		[[Knock sharedInstance] setLastScreenActivity:[NSDate date]];
	}
}

- (void)startListeningForKnock {
	if (!self.motionManager) {
		self.motionManager = [CMMotionManager new];
		self.motionManager.accelerometerUpdateInterval = KAccelUpdateInterval;
        [self.motionManager startAccelerometerUpdates];

        self.accelCheckTimer = [NSTimer scheduledTimerWithTimeInterval:0.01 target:self selector:@selector(checkAcceleration) userInfo:nil repeats:YES];
	}
}

- (void)stopListeningForKnock {
	if (self.motionManager) {
		[self.motionManager stopAccelerometerUpdates];
		self.motionManager = nil;

        [self.accelCheckTimer invalidate];
        self.accelCheckTimer = nil;
	}
}

- (id)init {
	self = [super init];

	_lastScreenActivity = [NSDate date];

	_possibleEvents = [NSMutableArray array];
	_lastEventPick = [NSDate date];

    _currentAccelX = _currentAccelY = _currentAccelZ = 0;

	[self startListeningForKnock];

	notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &_screenStateToken, dispatch_get_main_queue(), ^(int t) {
	    uint64_t state;
	    notify_get_state(_screenStateToken, &state);
	    if ((int)state == 1) {
	        [[Knock sharedInstance] stopListeningForKnock];
		}
	    else {
	        [[Knock sharedInstance] startListeningForKnock];
		}
	});

	IOHIDEventSystemClientRef ioHIDEventSystem = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
	IOHIDEventSystemClientScheduleWithRunLoop(ioHIDEventSystem, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	IOHIDEventSystemClientRegisterEventCallback(ioHIDEventSystem, handleSystemHIDEvent, NULL, NULL);

	return self;
}

+ (id)sharedInstance {
	static id knockInstance = nil;
	if (!knockInstance) {
		knockInstance = [Knock new];
	}
	return knockInstance;
}

+ (void)load {
	@autoreleasepool {
		[self sharedInstance];
	}
}

@end
