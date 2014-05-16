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

extern void FigVibratorPlayVibration(float, CMTime, CMTime, CMTime);
static void (*oldFigVibration)(float, CMTime, CMTime, CMTime);
static void newFigVibration(float arg1, CMTime arg2, CMTime arg3, CMTime arg4) {
    [[KVibrateListener sharedInstance] postVibratedEvent];
	return oldFigVibration(arg1, arg2, arg3, arg4);
}

- (void)hookFigVibration {
	MSHookFunction(FigVibratorPlayVibration, newFigVibration, (void *)&oldFigVibration);
}

extern void FigVibratorPlayVibrationWithDictionary(CFDictionaryRef pattern, BOOL, float);
static void (*oldFigDictionaryVibration)(CFDictionaryRef pattern, BOOL, float);
static void newFigDictionaryVibration(CFDictionaryRef pattern, BOOL arg2, float arg3) {
    [[KVibrateListener sharedInstance] postVibratedEvent];
	return oldFigDictionaryVibration(pattern, arg2, arg3);
}

- (void)hookFigDictionaryVibration {
	MSHookFunction(FigVibratorPlayVibrationWithDictionary, newFigDictionaryVibration, (void *)&oldFigDictionaryVibration);
}

extern void FigVibratorStartOneShot(int, int, int, int);
static void (*oldFigVibratorStart)(int, int, int, int);
static void newFigVibratorStart(int arg1, int arg2, int arg3, int arg4) {
    [[KVibrateListener sharedInstance] postVibratedEvent];
	return oldFigVibratorStart(arg1, arg2, arg3, arg4);
}

- (void)hookFigVibratorStart {
	MSHookFunction(FigVibratorStartOneShot, newFigVibratorStart, (void *)&oldFigVibratorStart);
}

- (id)init {
	self = [super init];

	[self hookSystemVibration];
	[self hookSystemSound];
    [self hookFigVibration];
    [self hookFigDictionaryVibration];
    [self hookFigVibratorStart];

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
