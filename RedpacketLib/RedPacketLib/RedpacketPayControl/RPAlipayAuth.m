//
//  RPAlipayAuth.m
//  RedpacketLib
//
//  Created by Mr.Yang on 2016/12/20.
//  Copyright © 2016年 Mr.Yang. All rights reserved.
//

#import "RPAlipayAuth.h"
#import "AlipaySDK.h"
#import "RPRedpacketBridge.h"
#import "RPRedpacketTool.h"
#import "UIAlertView+YZHAlert.h"


#define RPAlipayAuthAuthCodeKey     @"RPAlipayAuthAuthCodeKey"
#define RPAlipayAuthUserId          @"RPAlipayAuthUserId"


@interface RPAlipayAuth ()

@property (nonatomic,     copy) AlipayAuthCallBack authPaySuccess;
@property (nonatomic,   assign) BOOL isReceivedAuthResponse;
@property (nonatomic,     copy) NSString *authCode;
@property (nonatomic,     copy) NSString *authUserID;

@end


@implementation RPAlipayAuth

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(aliauthNotificationHandle:)
                                                     name:@"RedpacketAliAuthNotifaction" object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive)
                                                     name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)applicationDidBecomeActive
{
    [self performSelector:@selector(showDelayCancelAuth) withObject:nil afterDelay:.5];
}

- (void)showDelayCancelAuth
{
    if (!_isReceivedAuthResponse) {
        
        if (_authPaySuccess) {
            _authPaySuccess(NO, @"取消授权");
        }
        
    }
}

- (void)doAlipayAuth:(AlipayAuthCallBack)callBack
{
    self.authPaySuccess = callBack;
    [self requestAlipayAuthSign];
}

- (void)requestAlipayAuthSign
{
    rpWeakSelf;
    [RPRedpacketAliauth requestAliAuthSign:^(NSError *error, NSString *string) {
        
        if (!error) {
            
            [weakSelf doAlipayAuthWithSignString:string];
            
        } else {
            
            weakSelf.authPaySuccess(NO, error.localizedDescription);
            
        }
        
    }];
}

- (void)doAlipayAuthWithSignString:(NSString *)sign
{
    rpWeakSelf;
    [[AlipaySDK defaultService] auth_V2WithInfo:sign
                                     fromScheme:[[NSBundle mainBundle] bundleIdentifier]
                                       callback:^(NSDictionary *resultDic) {
                                           
                                           weakSelf.isReceivedAuthResponse = YES;
                                           
                                           NSString *errorStr = nil;
                                           
                                           if (resultDic && resultDic.allKeys.count) {
                                               
                                               //   网页版支付宝返回：resultStatus 9000
                                               //   支付宝APP返回：result_code 200
                                               NSInteger code = [resultDic[@"resultStatus"] integerValue];
                                               
                                               if (code == 0) {
                                                   
                                                   code = [resultDic[@"result_code"] integerValue];
                                                   
                                               }
                                               
                                               if (code == 200 || code == 9000) {
                                                   
                                                   [weakSelf handleAliAuthResult:resultDic];
                                                   return;
                                                   
                                               }else if (code == 6001) {
                                                   
                                                   errorStr = @"取消授权";
                                                   
                                               }else {
                                                   
                                                   errorStr = @"授权失败";
                                                   
                                               }
                                               
                                           }else {
                                               
                                               //   如果直接返回，则报用户取消授权
                                               errorStr = @"取消授权";
                                           }
                                           
                                           if (_authPaySuccess) {
                                               _authPaySuccess(NO, errorStr);
                                           }
                                           
                                       }];
}

//  delegate 处理完成之后，通过通知返回
- (void)aliauthNotificationHandle:(NSNotification *)notification
{
    self.isReceivedAuthResponse = YES;
    [self handleAliAuthResult:notification.object];
}

- (void)handleAliAuthResult:(NSDictionary *)resultDic
{
    RPDebug(@"Aliauth result = %@",resultDic);
    // 解析 auth code
    NSString *authCode = resultDic[@"auth_code"];
    NSString *userId = resultDic[@"user_id"];
    if (authCode.length) {
        
        //  APP版支付宝
        userId = [self URLDecodedString:userId];
        userId = [@"[" stringByAppendingString:userId];
        NSArray *conents = [userId componentsSeparatedByString:@"\",\""];
        userId = [[conents objectAtIndex:0] stringByReplacingOccurrencesOfString:@"userId:[" withString:@""];
        userId = [userId stringByReplacingOccurrencesOfString:@"[" withString:@""];
        
    }else {
        
        //  网页版支付宝
        NSString *result = [resultDic objectForKey:@"result"];
        NSArray *group = [result componentsSeparatedByString:@"&"];
        
        NSMutableDictionary *mutDic = [NSMutableDictionary dictionary];
        
        for (NSString *key in group) {
            
            NSArray *keyValue = [key componentsSeparatedByString:@"="];
            [mutDic setValue:keyValue[1] forKey:keyValue[0]];
            
        }
        
        userId = mutDic[@"user_id"];
        authCode = mutDic[@"auth_code"];
        
    }
    
    if (authCode.length && userId.length) {
        
        _authCode = authCode;
        _authUserID = userId;
        [self uploadAliAuthCode:authCode
                      andUserId:userId];
        
    }else {
        
        if (_authPaySuccess) {
            _authPaySuccess(NO, @"授权成功，但是检索用户信息失败");
        }
        
    }
    
    RPDebug(@"授权结果 authCode = %@", authCode?:@"");
}

- (void)uploadAliAuthCode:(NSString *)authCode
                andUserId:(NSString *)userId
{
    rpWeakSelf;
    [RPRedpacketAliauth uploadAliAuthInfo:authCode
                                   userID:userId
                          andRequsetBlock:^(NSError *error) {
        
        if (!error) {
            
            if (_authPaySuccess) {
                _authPaySuccess(YES, nil);
            }
            
        } else {
            
            [weakSelf alertUploadFailed];
            
        }
        
    }];
}

- (void)alertMessage:(NSString *)msg
{
    [[[UIAlertView alloc] initWithTitle:@"提示"
                                message:msg
                               delegate:nil
                      cancelButtonTitle:@"确定"
                      otherButtonTitles:nil] show];
}

- (void)alertUploadFailed
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"提示"
                                                    message:@"授权信息上传失败，请重试"
                                                   delegate:nil
                                          cancelButtonTitle:@"取消"
                                          otherButtonTitles:@"确定", nil];
    
    rpWeakSelf;
    [alert setRp_completionBlock:^(UIAlertView * alertView, NSInteger buttonIndex) {
        
        if (buttonIndex == 1) {
            
            [weakSelf uploadAliAuthCode:self.authCode
                              andUserId:self.authUserID];
            
        }else {
            
            if (weakSelf.authPaySuccess) {
                weakSelf.authPaySuccess(NO, @"授权信息上传失败");
            }
            
        }
        
    }];
    
    [alert show];
}

- (NSString *)URLDecodedString:(NSString *)str
{
    NSString *decodedString=(__bridge_transfer NSString *)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL, (__bridge CFStringRef)str, CFSTR(""), CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
    
    return decodedString;
}

@end
