
/*
     File: Controller.h
 Abstract: Central controller object for TextEdit, for implementing app functionality (services) as well
 as few tidbits for which there are no dedicated controllers.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>

@class Preferences, DocumentPropertiesPanelController, LinePanelController;

@interface Controller : NSObject {
    IBOutlet Preferences *preferencesController;
    IBOutlet DocumentPropertiesPanelController *propertiesController;
    IBOutlet LinePanelController *lineController;
}

@property (strong) Preferences *preferencesController;
@property (strong) DocumentPropertiesPanelController *propertiesController;
@property (strong) LinePanelController *lineController;

@end
