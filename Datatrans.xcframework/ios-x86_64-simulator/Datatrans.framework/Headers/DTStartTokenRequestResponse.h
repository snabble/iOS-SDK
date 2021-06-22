//
//  DTStartTokenRequestResponse.h
//  Datatrans
//
//  Created by Patrick Fompeyrine on 23.11.20.
//

#import <Datatrans/DTResponse.h>

@interface DTStartTokenRequestResponse : NSObject<DTResponse>

@property (nonatomic, assign) NSInteger responseCode;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, copy) NSString* transactionId;

@end
