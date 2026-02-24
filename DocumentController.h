
/*
     File: DocumentController.h
 Abstract: NSDocumentController subclass for TextEdit.
 Required to support transient documents and customized Open panel.
 
  Version: 1.8
 

 
 */

#import <Cocoa/Cocoa.h>
#import "Document.h"

/* An instance of this subclass is created in the main nib file. */

// NSDocumentController is subclassed to provide for modification of the open panel. Normally, there is no need to subclass the document controller.
@interface DocumentController : NSDocumentController

+ (NSView *)encodingAccessory:(NSUInteger)encoding includeDefaultEntry:(BOOL)includeDefaultItem encodingPopUp:(NSPopUpButton **)popup checkBox:(NSButton **)button;

- (Document *)openDocumentWithContentsOfPasteboard:(NSPasteboard *)pb display:(BOOL)display error:(NSError **)error;

- (NSStringEncoding)lastSelectedEncodingForURL:(NSURL *)url;
- (BOOL)lastSelectedIgnoreHTMLForURL:(NSURL *)url;
- (BOOL)lastSelectedIgnoreRichForURL:(NSURL *)url;

- (void)beginOpenPanel:(NSOpenPanel *)openPanel forTypes:(NSArray *)types completionHandler:(void (^)(NSInteger result))completionHandler;

- (Document *)transientDocumentToReplace;
- (void)displayDocument:(NSDocument *)doc;
- (void)replaceTransientDocument:(NSArray *)documents;

@end
