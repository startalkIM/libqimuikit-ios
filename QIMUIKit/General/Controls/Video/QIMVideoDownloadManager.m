//
//  QIMVideoDownloadManager.m
//  QTalkVideoPlayer
//
//  Created by qitmac000495 on 17/1/9.
//  Copyright © 2017年 lilu. All rights reserved.


#import "QIMVideoDownloadManager.h"
#import "QIMVideoCachePathTool.h"
#import "QIMVideoCacheManager.h"

@interface QIMVideoDownloadManager()<NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, assign) long long curOffset;

@property (nonatomic) NSUInteger fileLength;

@property (nonatomic, strong) NSString *mimeType;

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, assign) NSUInteger downLoadingOffset;

@property (nonatomic, assign) BOOL once;

@property (nonatomic, strong) NSOutputStream *outputStream;

@property (nonatomic, strong) NSString *tempPath;

@property(nonatomic, strong)NSString *suggestFileName;

@end


@implementation QIMVideoDownloadManager

#pragma mark --------------------------------------------------
#pragma mark Public

- (void)setUrl:(NSURL *)url offset:(long long)offset{
    
    _url = url;
    _curOffset = offset;
    _downLoadingOffset = 0;
    
    self.suggestFileName = [QIMVideoCachePathTool suggestFileNameWithURL:url];
    [self startLoading];
}

-(void)invalidateAndCancel{
    [self.session invalidateAndCancel];
}


#pragma mark --------------------------------------------------
#pragma mark NSURLSessionDataDelegate

// 接收到服务器响应
-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler{
    
     QIMVerboseLog(@"ReceiveResponse, 开始下载");
    _isFinishLoad = NO;
    _mimeType = @"video/mp4";
    
    // 拼接临时文件存储路径
    self.tempPath = [self getFileCachePath];
    // 获取文件总长度. 如果响应头里有文件长度数据, 就取这个长度; 如果没有, 就取代理方法返回给我们的长度
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
    NSDictionary *dic = (NSDictionary *)[httpResponse allHeaderFields] ;
    NSString *content = [dic valueForKey:@"Content-Range"];
    NSArray *array = [content componentsSeparatedByString:@"/"];
    NSString *length = array.lastObject;
    NSUInteger fileLength;
    if ([length integerValue] == 0) {
        fileLength = (NSUInteger)httpResponse.expectedContentLength;
    }
    else {
        fileLength = [length integerValue];
    }
    self.fileLength = fileLength;

    if ([self.delegate respondsToSelector:@selector(manager:didReceiveVideoLength:mimeType:)]) {
        [self.delegate manager:self didReceiveVideoLength:self.fileLength mimeType:self.mimeType];
    }
    
    self.outputStream = [[NSOutputStream alloc]initToFileAtPath:_tempPath append:YES];
    [self.outputStream open];
    completionHandler(NSURLSessionResponseAllow);
}

// 接收到服务器返回数据
-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data{
    
    if (data.length>0) {
        _downLoadingOffset += data.length;
        [self.outputStream write:data.bytes maxLength:data.length];
        
          QIMVerboseLog(@"loading ... 正在下载");
          QIMVerboseLog(@"Download progress --- %0.2lf", 1.0 * _downLoadingOffset / self.fileLength);
        
        if ([self.delegate respondsToSelector:@selector(manager:didReceiveData:downloadOffset:tempFilePath:)]) {
            [self.delegate manager:self didReceiveData:data downloadOffset:_downLoadingOffset tempFilePath:_tempPath];
        }
    }
}

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error{
    if (!error) {
        [self downloadSuccessWithURLSession:session task:task];
    }
    else{
        [self downloadFailedWithURLSession:session task:task error:error];
    }
}


#pragma mark --------------------------------------------------
#pragma mark Handle Request Finished(Success|Fail)

-(void)downloadSuccessWithURLSession:(NSURLSession *)session task:(NSURLSessionTask *)task{
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *savePath = [QIMVideoCachePathTool fileSavePath];
    savePath = [savePath stringByAppendingPathComponent:self.suggestFileName];
    
    if ([fileManager fileExistsAtPath:self.tempPath]) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
             [fileManager moveItemAtPath:self.tempPath toPath:savePath error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(didFinishLoadingWithManager:fileSavePath:)]) {
                    [self.delegate didFinishLoadingWithManager:self fileSavePath:savePath];
                }
            });
        });
    }
    
    [self.outputStream close];
    self.outputStream = nil;
}

-(void)downloadFailedWithURLSession:(NSURLSession *)session task:(NSURLSessionTask *)task error:(NSError *)error{
    
    //网络中断：-1005
    //无网络连接：-1009
    //请求超时：-1001
    //服务器内部错误：-1004
    //找不到服务器：-1003
    
    if (error.code == -1001 && !_once) {
        
        // 网络超时，重连
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startLoading];
            _once = YES;
        });
    }
    
    if ([self.delegate respondsToSelector:@selector(didFailLoadingWithManager:WithError:)]) {
        [self.delegate didFailLoadingWithManager:self WithError:error];
    }
    
    if (error.code == -1009) {
        QIMVerboseLog(@"No Connect 无网络连接");
    }
}


#pragma mark --------------------------------------------------
#pragma mark Private

-(NSString *)getFileCachePath{
    NSString *path = [QIMVideoCachePathTool fileCachePath];
    path = [path stringByAppendingPathComponent:self.suggestFileName];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:path] && !self.once) {
        [fileManager removeItemAtPath:path error:nil];
        [fileManager createFileAtPath:path contents:nil attributes:nil];
    }
    else {
        [fileManager createFileAtPath:path contents:nil attributes:nil];
    }
    return path;
}

- (void)clearData{
    [self.session invalidateAndCancel];
    [self.outputStream close];
    self.outputStream = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_tempPath error:nil];
}

-(void)startLoading{
    
    // 替代NSMutableURL, 可以动态修改scheme
    NSURLComponents *actualURLComponents = [[NSURLComponents alloc] initWithURL:_url resolvingAgainstBaseURL:NO];
    actualURLComponents.scheme = @"http";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[actualURLComponents URL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:20.0];
    
    // 修改请求数据范围
    if (_curOffset > 0 && self.fileLength > 0) {
        [request addValue:[NSString stringWithFormat:@"bytes=%ld-%ld",(unsigned long)_curOffset, (unsigned long)self.fileLength - 1] forHTTPHeaderField:@"Range"];
    }
    // 重置
    [self.session invalidateAndCancel];
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request];
    [dataTask resume];
}

@end
