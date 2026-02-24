
/*
     File: Controller.m
 Abstract: Central controller object for TextEdit, for implementing app
 functionality (services) as well as few tidbits for which there are no
 dedicated controllers.

  Version: 1.8



 */

#import "Controller.h"
#import "Document.h"
#import "DocumentController.h"
#import "EncodingManager.h"
#import "TextEditDefaultsKeys.h"
#import "TextEditErrors.h"
#import "TextEditMisc.h"
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSDictionary *defaultValues() {
  static NSDictionary *dict = nil;
  if (!dict) {
    dict = [[NSDictionary alloc]
        initWithObjectsAndKeys:
            [NSNumber numberWithInteger:30], AutosavingDelay, [NSNumber numberWithBool:NO],
            NumberPagesWhenPrinting, [NSNumber numberWithBool:YES], WrapToFitWhenPrinting,
            [NSNumber numberWithBool:YES], RichText, [NSNumber numberWithBool:NO], ShowPageBreaks,
            [NSNumber numberWithBool:NO], OpenPanelFollowsMainWindow, [NSNumber numberWithBool:YES],
            AddExtensionToNewPlainTextFiles, [NSNumber numberWithInteger:90], WindowWidth,
            [NSNumber numberWithInteger:30], WindowHeight,
            [NSNumber numberWithUnsignedInteger:NoStringEncoding], PlainTextEncodingForRead,
            [NSNumber numberWithUnsignedInteger:NoStringEncoding], PlainTextEncodingForWrite,
            [NSNumber numberWithInteger:8], TabWidth, [NSNumber numberWithInteger:50000],
            ForegroundLayoutToIndex, [NSNumber numberWithBool:NO], IgnoreRichText,
            [NSNumber numberWithBool:NO], IgnoreHTML, [NSNumber numberWithBool:YES],
            CheckSpellingAsYouType, [NSNumber numberWithBool:NO], CheckGrammarWithSpelling,
            [NSNumber numberWithBool:[NSSpellChecker isAutomaticSpellingCorrectionEnabled]],
            CorrectSpellingAutomatically, [NSNumber numberWithBool:YES], ShowRuler,
            [NSNumber numberWithBool:YES], SmartCopyPaste, [NSNumber numberWithBool:NO],
            SmartQuotes, [NSNumber numberWithBool:NO], SmartDashes, [NSNumber numberWithBool:NO],
            SmartLinks, [NSNumber numberWithBool:NO], DataDetectors,
            [NSNumber numberWithBool:[NSSpellChecker isAutomaticTextReplacementEnabled]],
            TextReplacement, [NSNumber numberWithBool:NO], SubstitutionsEnabledInRichTextOnly, @"",
            AuthorProperty, @"", CompanyProperty, @"", CopyrightProperty,
            [NSNumber numberWithBool:NO], UseXHTMLDocType, [NSNumber numberWithBool:NO],
            UseTransitionalDocType, [NSNumber numberWithBool:YES], UseEmbeddedCSS,
            [NSNumber numberWithBool:NO], UseInlineCSS,
            [NSNumber numberWithUnsignedInteger:NSUTF8StringEncoding], HTMLEncoding,
            [NSNumber numberWithBool:YES], PreserveWhitespace, [NSNumber numberWithBool:NO],
            UseScreenFonts, nil];
  }
  return dict;
}

@implementation Controller

+ (void)initialize {
  // Set up default values for preferences managed by NSUserDefaultsController
  [[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues()];
  [[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:defaultValues()];
#if __LP64__
  // At some point during 32-to-64 bit transition of TextEdit, some versions
  // erroneously wrote out the value of -1 to defaults. These values cause grief
  // throughout the program under 64-bit, so it's best to clean them out from
  // defaults permanently. Note that it's often considered bad form to write
  // defaults while launching; however, here we do this only once, ever.
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([[defaults objectForKey:PlainTextEncodingForRead] unsignedIntegerValue] ==
      0xFFFFFFFFFFFFFFFFULL) {
    [defaults removeObjectForKey:PlainTextEncodingForRead];
  }
  if ([[defaults objectForKey:PlainTextEncodingForWrite] unsignedIntegerValue] ==
      0xFFFFFFFFFFFFFFFFULL) {
    [defaults removeObjectForKey:PlainTextEncodingForWrite];
  }
#endif
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  // To get service requests to go to the controller...
  [NSApp setServicesProvider:self];
}

/*** Services support ***/

- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error {
  NSString *filename, *origFilename;
  NSURL *url = nil;
  NSString *type =
      [pboard availableTypeFromArray:[NSArray arrayWithObject:UTTypePlainText.identifier]];

  if (type && (filename = origFilename = [pboard stringForType:type])) {
    if ([filename isAbsolutePath]) {
      url = [NSURL fileURLWithPath:filename];
    }
    if (!url) {
      // Check to see if the user mistakenly included a carriage return or more
      // at the end of the file name...
      filename = [[filename substringWithRange:[filename lineRangeForRange:NSMakeRange(0, 0)]]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([filename hasPrefix:@"~"]) {
        filename = [filename stringByExpandingTildeInPath];
      }
      if (![origFilename isEqual:filename] && [filename isAbsolutePath]) {
        url = [NSURL fileURLWithPath:filename];
      }
    }
    if (url) {
      [[NSDocumentController sharedDocumentController]
          openDocumentWithContentsOfURL:url
                                display:YES
                      completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen,
                                          NSError *openError) {
                        if (!document) {
                          NSError *alertError =
                              openError
                                  ?: [NSError errorWithDomain:NSCocoaErrorDomain
                                                         code:NSFileReadInvalidFileNameError
                                                     userInfo:[NSDictionary
                                                                  dictionaryWithObjectsAndKeys:
                                                                      truncatedString(
                                                                          filename, PATH_MAX + 10),
                                                                      NSFilePathErrorKey, nil]];
                          [[NSAlert alertWithError:alertError] runModal];
                        }
                      }];
    } else {
      NSError *alertError = [NSError
          errorWithDomain:NSCocoaErrorDomain
                     code:NSFileReadInvalidFileNameError
                 userInfo:[NSDictionary
                              dictionaryWithObjectsAndKeys:truncatedString(filename, PATH_MAX + 10),
                                                           NSFilePathErrorKey, nil]];
      [[NSAlert alertWithError:alertError] runModal];
    }
  }
}

/* The following, apart from providing the service through the Services menu,
 * allows the user to drop snippets of text on the TextEdit icon and have it
 * open as a new document. */
- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error {
  NSError *err = nil;
  Document *document = [(DocumentController *)[NSDocumentController sharedDocumentController]
      openDocumentWithContentsOfPasteboard:pboard
                                   display:YES
                                     error:&err];

  if (!document) {
    [[NSAlert alertWithError:err] runModal];
    // No need to report an error string...
  }
}

@end
