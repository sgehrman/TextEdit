
/*
     File: Controller.h
 Abstract: Central controller object for TextEdit, for implementing app functionality (services) as well
 as few tidbits for which there are no dedicated controllers.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>

@class Preferences, DocumentPropertiesPanelController, LinePanelController;

@interface Controller : NSObject

@property (nonatomic, strong) IBOutlet Preferences *preferencesController;
@property (nonatomic, strong) IBOutlet DocumentPropertiesPanelController *propertiesController;
@property (nonatomic, strong) IBOutlet LinePanelController *lineController;

@end
