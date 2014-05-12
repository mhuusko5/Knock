#import <Foundation/Foundation.h>

@interface KEvent : NSObject

@property NSString *name;
@property float score;

- (id)initWithName:(NSString *)name score:(float)score;

@end
