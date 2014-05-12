#import <libactivator/libactivator.h>
#import <notify.h>
#import <CoreMotion/CoreMotion.h>
#include "IOHIDEventSystem.h"
#include "IOHIDEventSystemClient.h"

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);

static float KFilteringFactor = 0.1;
static float KAccelUpdateInterval = 1 / 100.0;
static NSString *KEventNameSide = @"com.mhuusko5.Knock.side";
static NSString *KEventNameFront = @"com.mhuusko5.Knock.front";

@interface KEvent : NSObject

@property NSString *event;
@property float delta;

- (id)initWithEvent:(NSString *)event delta:(float)delta;

@end

@implementation KEvent

- (id)initWithEvent:(NSString *)event delta:(float)delta {
	self = [super init];

	_event = event;
	_delta = delta;

	return self;
}

@end

@interface Knock : NSObject

@property CMMotionManager *motionManager;
@property CMAcceleration newAcceleration;
@property float currentAccelX, currentAccelY, currentAccelZ;
@property int screenStateToken;
@property NSDate *lastScreenActivity;
@property NSMutableArray *possibleEvents;
@property NSDate *lastEventPick;

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

	_lastScreenActivity = [NSDate date];

	_possibleEvents = [NSMutableArray array];
	_lastEventPick = [NSDate date];

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

void handleSystemHIDEvent(void *target, void *refcon, IOHIDEventQueueRef queue, IOHIDEventRef event) {
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

- (void)checkPossibleEvents {
	NSArray *sortedEvents = [self.possibleEvents sortedArrayUsingComparator: ^NSComparisonResult (KEvent *event1, KEvent *event2) {
	    return [@(event2.delta)compare: @(event1.delta)];
	}];

    self.possibleEvents = [NSMutableArray array];

	KEvent *mostForcefulEvent = sortedEvents[0];

	[LASharedActivator sendEventToListener:[LAEvent eventWithName:mostForcefulEvent.event mode:[LASharedActivator currentEventMode]]];
}

- (void)storePossibleEventWithDelta:(float)accelDelta name:(NSString *)eventName {
    [self.possibleEvents addObject:[[KEvent alloc] initWithEvent:eventName delta:accelDelta]];

    if ([self.lastEventPick timeIntervalSinceNow] * -1000 > 150 && self.possibleEvents.count > 0) {
        [self checkPossibleEvents];

        self.lastEventPick = [NSDate date];
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

    if ([self.lastScreenActivity timeIntervalSinceNow] * -1000 > 500) {
        float deltaX = ABS(self.currentAccelX - prevAccelX);
        float deltaY = ABS(self.currentAccelY - prevAccelY);
        float deltaZ = ABS(self.currentAccelZ - prevAccelZ);

        if (deltaX > 1.1) {
            [self storePossibleEventWithDelta:deltaX name:KEventNameSide];
        }

        if (deltaZ > 1.8) {
            [self storePossibleEventWithDelta:deltaZ name:KEventNameFront];
        }
    }
}

@end
