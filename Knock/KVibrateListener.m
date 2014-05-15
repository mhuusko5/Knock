#import "KVibrateListener.h"

@implementation KVibrateListener

- (void)postVibratedEvent {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.mhuusko5.Knock.vibrated"), NULL, NULL, true);
}

extern void AudioServicesPlaySystemSoundWithVibration(SystemSoundID inSystemSoundID, void *arg, NSDictionary *vibratePattern);

static void (*oldSystemVibration)(SystemSoundID inSystemSoundID, void *arg, NSDictionary *vibratePattern);
static void newSystemVibration(SystemSoundID inSystemSoundID, void *arg, NSDictionary *vibratePattern) {
	[[KVibrateListener sharedInstance] postVibratedEvent];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
	    [[KVibrateListener sharedInstance] postVibratedEvent];
	});
	return oldSystemVibration(inSystemSoundID, arg, vibratePattern);
}

- (void)hookSystemVibration {
	MSHookFunction(AudioServicesPlaySystemSoundWithVibration, newSystemVibration, (void *)&oldSystemVibration);
}

static void (*oldSystemSound)(SystemSoundID inSystemSoundID);
static void newSystemSound(SystemSoundID inSystemSoundID) {
	if (inSystemSoundID == 4095 || inSystemSoundID == 1351 || inSystemSoundID == 1350 || inSystemSoundID == 1311 || inSystemSoundID == 1107 || inSystemSoundID == 1011) {
		[[KVibrateListener sharedInstance] postVibratedEvent];
	}
	return oldSystemSound(inSystemSoundID);
}

- (void)hookSystemSound {
	MSHookFunction(AudioServicesPlaySystemSound, newSystemSound, (void *)&oldSystemSound);
}

static void * (*oldDlsym)(void *__handle, const char *__symbol);
static void *newDlsym(void *__handle, const char *__symbol) {
	void *_return = oldDlsym(__handle, __symbol);

	NSString *function = [NSString stringWithUTF8String:__symbol];
	if ([function isEqualToString:@"AudioServicesPlaySystemSound"]) {
		[[KVibrateListener sharedInstance] hookSystemSound];
	}
	else if ([function isEqualToString:@"AudioServicesPlaySystemSoundWithVibration"]) {
		[[KVibrateListener sharedInstance] hookSystemVibration];
	}

	return _return;
}

- (void)hookDlsym {
	MSHookFunction(dlsym, newDlsym, (void *)&oldDlsym);
}

- (id)init {
	self = [super init];

	[self hookSystemVibration];
	[self hookSystemSound];
	//[self hookDlsym];

	return self;
}

+ (id)sharedInstance {
	static dispatch_once_t onceToken;
	static id instance;
	dispatch_once(&onceToken, ^{
	    instance = self.new;
	});
	return instance;
}

@end
