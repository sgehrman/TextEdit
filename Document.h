
/*
     File: Document.h
 Abstract: Document object for TextEdit. 
 
  Version: 1.8
 
 Document.h isn't using @property and probably other files too.  Could you
   modernize the all the code with properties?
 
 */

#import <Cocoa/Cocoa.h>

@interface Document : NSDocument

/* Document data */
@property (nonatomic, readonly, strong) NSTextStorage *textStorage;
@property (nonatomic, assign) CGFloat scaleFactor;
@property (nonatomic, assign, getter=isReadOnly) BOOL readOnly;
@property (nonatomic, copy) NSColor *backgroundColor;
@property (nonatomic, assign) float hyphenationFactor;
@property (nonatomic, assign) NSSize viewSize;
@property (nonatomic, assign) BOOL hasMultiplePages;
@property (nonatomic, assign) BOOL usesScreenFonts;

/* Document properties (applicable only to rich text documents) */
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *copyright;
@property (nonatomic, copy) NSString *company;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *comment;
@property (nonatomic, copy) NSArray *keywords;

/* Information about how the document was created */
@property (nonatomic, assign, getter=isOpenedIgnoringRichText) BOOL openedIgnoringRichText;
@property (nonatomic, assign) NSStringEncoding encoding;
@property (nonatomic, assign) NSStringEncoding encodingForSaving;
@property (nonatomic, assign, getter=isConverted) BOOL converted;
@property (nonatomic, assign, getter=isLossy) BOOL lossy;
@property (nonatomic, assign, getter=isTransient) BOOL transient;
@property (nonatomic, copy) NSArray *originalOrientationSections;

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName encoding:(NSStringEncoding)encoding ignoreRTF:(BOOL)ignoreRTF ignoreHTML:(BOOL)ignoreHTML error:(NSError **)outError;

/* Is the document rich? */
- (BOOL)isRichText;

/* Scripting support: copies contents into textStorage */
- (void)setTextStorage:(id)ts;

/* Page-oriented methods */
- (NSSize)paperSize;
- (void)setPaperSize:(NSSize)size;

/* Action methods */
- (IBAction)toggleReadOnly:(id)sender;
- (IBAction)togglePageBreaks:(id)sender;
- (IBAction)saveDocumentAsPDFTo:(id)sender;

/* Whether conversion to rich/plain be done without loss of information */
- (BOOL)toggleRichWillLoseInformation;

/* Default text attributes for plain or rich text formats */
- (NSDictionary *)defaultTextAttributes:(BOOL)forRichText;
- (void)applyDefaultTextAttributes:(BOOL)forRichText;

/* Document properties */
- (NSDictionary *)documentPropertyToAttributeNameMappings;
- (NSArray *)knownDocumentProperties;
- (void)clearDocumentProperties;
- (void)setDocumentPropertiesToDefaults;
- (BOOL)hasDocumentProperties;

/* Transient documents */
- (BOOL)isTransientAndCanBeReplaced;

@end
