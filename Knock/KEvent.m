#import "KEvent.h"

@implementation KEvent

- (id)initWithName:(NSString *)name score:(float)score {
	self = [super init];

	_name = name;
	_score = score;

	return self;
}

@end