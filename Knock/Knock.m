#import <libactivator/libactivator.h>
#import <notify.h>
#import <CoreMotion/CoreMotion.h>
#include "IOHIDEventSystem.h"
#include "IOHIDEventSystemClient.h"

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);

static float KFilteringFactor = 0.3;
static float KDeltaMinimum = 1.0;
static float KAccelUpdateInterval = 1 / 100.0;
static NSString *KEventNameTop = @"com.mhuusko5.Knock.top";
static NSString *KEventNameSide = @"com.mhuusko5.Knock.side";
static NSString *KEventNameFront = @"com.mhuusko5.Knock.front";

@interface Knock : NSObject

@property CMMotionManager *motionManager;
@property CMAcceleration newAcceleration;
@property float currentAccelX, currentAccelY, currentAccelZ;
@property int screenStateToken;
@property NSDate *lastEventSend;
@property NSDate *lastScreenActivity;

@end

@implementation Knock

+ (void)load {
	@autoreleasepool {
		[self sharedInstance];
	}
}

+ (id)sharedInstance {
	static id knockInstance = nil;
	if (!knockInstance) {
		knockInstance = [Knock new];
	}
	return knockInstance;
}

- (id)init {
	self = [super init];

    _lastEventSend = [NSDate date];
    _lastScreenActivity = [NSDate date];

	[self startListeningForKnock];

    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &_screenStateToken, dispatch_get_main_queue(), ^(int t) {
	    uint64_t state;
	    notify_get_state(_screenStateToken, &state);
	    if ((int)state == 1) {
            [[Knock sharedInstance] stopListeningForKnock];
        } else {
            [[Knock sharedInstance] startListeningForKnock];
        }
	});

    IOHIDEventSystemClientRef ioHIDEventSystem = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventSystemClientScheduleWithRunLoop(ioHIDEventSystem, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDEventSystemClientRegisterEventCallback(ioHIDEventSystem, handleSystemHIDEvent, NULL, NULL);

	return self;
}

void handleSystemHIDEvent(void* target, void* refcon, IOHIDEventQueueRef queue, IOHIDEventRef event) {
    if (IOHIDEventGetType(event) == kIOHIDEventTypeDigitizer) {
        [[Knock sharedInstance] setLastScreenActivity:[NSDate date]];
    }
}

- (void)stopListeningForKnock {
	if (self.motionManager) {
		[self.motionManager stopAccelerometerUpdates];
		self.motionManager = nil;
	}
}

- (void)startListeningForKnock {
	if (!self.motionManager) {
		self.motionManager = [CMMotionManager new];
		self.motionManager.accelerometerUpdateInterval = KAccelUpdateInterval;

		__weak typeof(self) this = self;

		[self.motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue new] withHandler:
		 ^(CMAccelerometerData *accelerometerData, NSError *error) {
		    [this setNewAcceleration:accelerometerData.acceleration];
		    [self performSelectorOnMainThread:@selector(checkAcceleration) withObject:nil waitUntilDone:NO];
		}];
	}
}

- (void)checkPossibleEventWithDelta:(float)accelDelta name:(NSString *)eventName {
    if ([self.lastEventSend timeIntervalSinceNow] * -1000 > 250 && [self.lastScreenActivity timeIntervalSinceNow] * -1000 > 200) {
        if ([eventName isEqualToString:KEventNameTop]) {
            eventName = KEventNameSide;
        }

        [LASharedActivator sendEventToListener:[LAEvent eventWithName:eventName mode:[LASharedActivator currentEventMode]]];

        self.lastEventSend = [NSDate date];
    }
}

- (void)checkAcceleration {
	CMAcceleration newAcceleration = self.newAcceleration;

	float prevAccelX = self.currentAccelX;
	float prevAccelY = self.currentAccelY;
	float prevAccelZ = self.currentAccelZ;
	self.currentAccelX = newAcceleration.x - ((newAcceleration.x * KFilteringFactor) + (self.currentAccelX * (1.0 - KFilteringFactor)));
	self.currentAccelY = newAcceleration.y - ((newAcceleration.y * KFilteringFactor) + (self.currentAccelY * (1.0 - KFilteringFactor)));
	self.currentAccelZ = newAcceleration.z - ((newAcceleration.z * KFilteringFactor) + (self.currentAccelZ * (1.0 - KFilteringFactor)));

	float deltaX = ABS(self.currentAccelX - prevAccelX);
	float deltaY = ABS(self.currentAccelY - prevAccelY);
	float deltaZ = ABS(self.currentAccelZ - prevAccelZ);

	if (deltaX > KDeltaMinimum * 0.9 && deltaX > deltaY && deltaX > deltaZ) {
		[self checkPossibleEventWithDelta:deltaX name:KEventNameSide];
	}
	else if (deltaY > KDeltaMinimum * 0.9 && deltaY > deltaX && deltaY > deltaZ) {
		[self checkPossibleEventWithDelta:deltaY name:KEventNameTop];
	}
	else if (deltaZ > KDeltaMinimum * 1.1 && deltaZ > deltaX && deltaZ > deltaY) {
		[self checkPossibleEventWithDelta:deltaZ name:KEventNameFront];
	}
}

@end
