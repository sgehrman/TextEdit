
/*
     File: PrintPanelAccessoryController.m
 Abstract: PrintPanelAccessoryController is a subclass of NSViewController demonstrating how to add an accessory view to the print panel.
 
  Version: 1.8
 

 
 */

#import "PrintPanelAccessoryController.h"
#import "TextEditDefaultsKeys.h"


@implementation PrintPanelAccessoryController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    // We override the designated initializer, ignoring the nib since we need our own
    return [super initWithNibName:@"PrintPanelAccessory" bundle:nibBundleOrNil];
}

/* The first time the printInfo is supplied, initialize the value of the pageNumbering setting from defaults
 */
- (void)setRepresentedObject:(id)printInfo {
    [super setRepresentedObject:printInfo];
    [self setPageNumbering:[[[NSUserDefaults standardUserDefaults] objectForKey:NumberPagesWhenPrinting] boolValue]];
    [self setWrappingToFit:[[[NSUserDefaults standardUserDefaults] objectForKey:WrapToFitWhenPrinting] boolValue]];
}

- (void)setPageNumbering:(BOOL)flag {
    NSPrintInfo *printInfo = [self representedObject];
    [[printInfo dictionary] setObject:[NSNumber numberWithBool:flag] forKey:NSPrintHeaderAndFooter];
}

- (BOOL)pageNumbering {
    NSPrintInfo *printInfo = [self representedObject];
    return [[[printInfo dictionary] objectForKey:NSPrintHeaderAndFooter] boolValue];
}

- (IBAction)changePageNumbering:(id)sender {
    [self setPageNumbering:[sender state] ? YES : NO];
}

- (IBAction)changeWrappingToFit:(id)sender {
    [self setWrappingToFit:[sender state] ? YES : NO];
}

- (NSSet *)keyPathsForValuesAffectingPreview {
    return [NSSet setWithObjects:@"pageNumbering", @"wrappingToFit", nil];
}

/* This enables TextEdit-specific settings to be displayed in the Summary pane of the print panel.
*/
- (NSArray *)localizedSummaryItems {
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                      NSLocalizedStringFromTable(@"Header and Footer", @"PrintPanelAccessory", @"Print panel summary item title for whether header and footer (page number, date, document title) should be printed"), NSPrintPanelAccessorySummaryItemNameKey,
                      [self pageNumbering] ? NSLocalizedStringFromTable(@"On", @"PrintPanelAccessory", @"Print panel summary value for feature that is enabled") : NSLocalizedStringFromTable(@"Off", @"PrintPanelAccessory", @"Print panel summary value for feature that is disabled"), NSPrintPanelAccessorySummaryItemDescriptionKey,
                      nil]];
    // We add the "Rewrap to fit page" item to the summary only if the item is settable (which it isn't, for "wrap-to-page" mode)
    if ([self showsWrappingToFit]) [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                                     NSLocalizedStringFromTable(@"Rewrap to fit page", @"PrintPanelAccessory", @"Print panel summary item title for whether document contents should be rewrapped to fit the page"), NSPrintPanelAccessorySummaryItemNameKey,
                                                     [self wrappingToFit] ? NSLocalizedStringFromTable(@"On", @"PrintPanelAccessory", @"Print panel summary value for feature that is enabled") : NSLocalizedStringFromTable(@"Off", @"PrintPanelAccessory", @"Print panel summary value for feature that is disabled"), NSPrintPanelAccessorySummaryItemDescriptionKey,
                                                     nil]];
    return items;
}

@end
