
/*
     File: TextEditErrors.h
 Abstract: Definition of TextEdit-specific error domain and codes for NSError.
 
  Version: 1.8
 

 
 */

#define TextEditErrorDomain @"com.apple.TextEdit"

enum {
    TextEditSaveErrorConvertedDocument = 1,
    TextEditSaveErrorLossyDocument = 2,
    TextEditSaveErrorWritableTypeRequired = 3, 
    TextEditSaveErrorEncodingInapplicable = 4,
    TextEditOpenDocumentWithSelectionServiceFailed = 100,
    TextEditInvalidLineSpecification = 200,
    TextEditOutOfRangeLineSpecification = 201,
    TextEditAttachFilesFailure = 300
};


