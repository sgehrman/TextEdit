
/*
     File: FontNameTransformer.m
 Abstract: Value transformer that turns fonts into a human-readable string with the font's name and size. This is used in the preferences window.
 
  Version: 1.8
 

 
 */

#import "FontNameTransformer.h"


@implementation FontNameTransformer
+ (Class)tranformedValueClass {
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation {
    return NO;
}

- (id)transformedValue:(id)value {
    if (value && [value isKindOfClass:[NSFont class]]) {
        return [NSString stringWithFormat:@"%@ %g", [value displayName], [value pointSize]];
    } else {
        return @"";
    }
}

@end
