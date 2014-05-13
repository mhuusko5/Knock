#import <libactivator/libactivator.h>
#import <notify.h>
#import <CoreMotion/CoreMotion.h>
#include "IOHIDEventSystem.h"
#include "IOHIDEventSystemClient.h"
#import "KEvent.h"

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);

static float KFilteringFactor = 0.25;
static float KMinimumSideDelta = 0.85;
static float KMinimumFrontDelta = 0.9;
static float KAccelUpdateInterval = 0.01;
static float KMaximumAlternateAccel = 1.0;
static float KMinimumIntervalSinceMaxAltAccel = 0.2;
static NSString *KEventNameSide = @"com.mhuusko5.Knock.side";
static NSString *KEventNameFront = @"com.mhuusko5.Knock.front";

@interface Knock : NSObject

@property CMMotionManager *motionManager;
@property NSTimer *accelCheckTimer;
@property float currentAccelX, currentAccelY, currentAccelZ;
@property int screenStateToken;
@property NSDate *lastScreenActivity;
@property NSMutableArray *possibleEvents;
@property NSDate *lastMaxXAccel, *lastMaxYAccel, *lastMaxZAccel;

@end

@implementation Knock

- (void)checkPossibleEvents {
    if (self.possibleEvents.count > 0) {
		NSArray *sortedEvents = [self.possibleEvents sortedArrayUsingComparator: ^NSComparisonResult (KEvent *event1, KEvent *event2) {
		    return [@(event2.score)compare : @(event1.score)];
		}];

        self.possibleEvents = [NSMutableArray array];

        NSString *eventName = [sortedEvents[0] name];

        if (([eventName isEqualToString:KEventNameFront] && (-[self.lastMaxXAccel timeIntervalSinceNow] < KMinimumIntervalSinceMaxAltAccel || -[self.lastMaxYAccel timeIntervalSinceNow] < KMinimumIntervalSinceMaxAltAccel)) || ([eventName isEqualToString:KEventNameSide] && (-[self.lastMaxZAccel timeIntervalSinceNow] < KMinimumIntervalSinceMaxAltAccel || -[self.lastMaxYAccel timeIntervalSinceNow] < KMinimumIntervalSinceMaxAltAccel))) {
            return;
        }

        NSLog(@"%@ %f", [sortedEvents[0] name], [sortedEvents[0] score]);

        [LASharedActivator sendEventToListener:[LAEvent eventWithName:[sortedEvents[0] name] mode:[LASharedActivator currentEventMode]]];
	}
}

- (void)addPossibleEvent:(KEvent *)event {
    [self.possibleEvents addObject:event];

    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self performSelector:@selector(checkPossibleEvents) withObject:nil afterDelay:0.05];
}

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
    float deltaX = ABS(self.currentAccelX - prevAccelX);
	float deltaY = ABS(self.currentAccelY - prevAccelY);
	float deltaZ = ABS(self.currentAccelZ - prevAccelZ);

    if (ABS(self.currentAccelX) > KMaximumAlternateAccel) {
        self.lastMaxXAccel = [NSDate date];
    }

    if (ABS(self.currentAccelY) > KMaximumAlternateAccel) {
        self.lastMaxYAccel = [NSDate date];
    }

    if (ABS(self.currentAccelZ) > KMaximumAlternateAccel) {
        self.lastMaxZAccel = [NSDate date];
    }

	if (deltaX > KMinimumSideDelta) {
        [self addPossibleEvent:[[KEvent alloc] initWithName:KEventNameSide score:deltaX / KMinimumSideDelta]];
	}

	if (deltaZ > KMinimumFrontDelta) {
		[self addPossibleEvent:[[KEvent alloc] initWithName:KEventNameFront score:deltaZ / KMinimumFrontDelta]];
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

void handleSystemHIDEvent(void *target, void *refcon, IOHIDEventQueueRef queue, IOHIDEventRef event) {
	if (IOHIDEventGetType(event) == kIOHIDEventTypeDigitizer) {
		[[Knock sharedInstance] setLastScreenActivity:[NSDate date]];
        [NSObject cancelPreviousPerformRequestsWithTarget:[Knock sharedInstance]];
	}
}

- (id)init {
	self = [super init];

	_lastScreenActivity = [NSDate date];

	_possibleEvents = [NSMutableArray array];

	_currentAccelX = _currentAccelY = _currentAccelZ = 0;

    _lastMaxXAccel = [NSDate date];
    _lastMaxYAccel = [NSDate date];
    _lastMaxZAccel = [NSDate date];

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
	static dispatch_once_t once;
	static id instance;
	dispatch_once(&once, ^{
	    instance = self.new;
	});
	return instance;
}

+ (void)load {
	@autoreleasepool {
		[self sharedInstance];
	}
}

@end
