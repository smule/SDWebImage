/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import "SDImageCache.h"
#import "SDWebImageDownloader.h"
#import <objc/message.h>

static SDWebImageManager *instance;

// added by smule
static NSString *kCircleCacheKeyAddition = @"-circle";

NSString *const kMaxImageSizeForCacheKey = @"kMaxImageSizeForCacheKey";

@implementation SDWebImageManager

#if NS_BLOCKS_AVAILABLE
@synthesize cacheKeyFilter;
#endif

- (id)init
{
    if ((self = [super init]))
    {
        downloadInfo = [[NSMutableArray alloc] init];
        downloadDelegates = [[NSMutableArray alloc] init];
        downloaders = [[NSMutableArray alloc] init];
        cacheDelegates = [[NSMutableArray alloc] init];
        cacheURLs = [[NSMutableArray alloc] init];
        downloaderForURL = [[NSMutableDictionary alloc] init];
        failedURLs = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    SDWISafeRelease(downloadInfo);
    SDWISafeRelease(downloadDelegates);
    SDWISafeRelease(downloaders);
    SDWISafeRelease(cacheDelegates);
    SDWISafeRelease(cacheURLs);
    SDWISafeRelease(downloaderForURL);
    SDWISafeRelease(failedURLs);
    SDWISuperDealoc;
}


+ (id)sharedManager
{
    if (instance == nil)
    {
        instance = [[SDWebImageManager alloc] init];
    }
    
    return instance;
}

- (NSString *)cacheKeyForURL:(NSURL *)url
{
#if NS_BLOCKS_AVAILABLE
    if (self.cacheKeyFilter)
    {
        return self.cacheKeyFilter(url);
    }
    else
    {
        return [url absoluteString];
    }
#else
    return [url absoluteString];
#endif
}

- (NSString*)cacheKeyForURL:(NSURL*)url withOptions:(SDWebImageOptions)options userInfo:(NSDictionary*)userInfo
{
    // added by smule
    NSString *cacheKey = [self cacheKeyForURL:url];
    // append a different cache key if we're drawing a circle
    if ((options & SDWebImageCircleImageToCache))
    {
        cacheKey = [cacheKey stringByAppendingString:kCircleCacheKeyAddition];
    }
    NSString *newSize = [userInfo objectForKey:kMaxImageSizeForCacheKey];
    if ( newSize )
    {
        cacheKey = [cacheKey stringByAppendingString:newSize];
    }
    return cacheKey;
}

/*
 * @deprecated
 */
- (UIImage *)imageWithURL:(NSURL *)url
{
    return [[SDImageCache sharedImageCache] imageFromKey:[self cacheKeyForURL:url]];
}

/*
 * @deprecated
 */
- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate retryFailed:(BOOL)retryFailed
{
    [self downloadWithURL:url delegate:delegate options:(retryFailed ? SDWebImageRetryFailed : 0)];
}

/*
 * @deprecated
 */
- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate retryFailed:(BOOL)retryFailed lowPriority:(BOOL)lowPriority
{
    SDWebImageOptions options = 0;
    if (retryFailed) options |= SDWebImageRetryFailed;
    if (lowPriority) options |= SDWebImageLowPriority;
    [self downloadWithURL:url delegate:delegate options:options];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate
{
    [self downloadWithURL:url delegate:delegate options:0];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate options:(SDWebImageOptions)options
{
    [self downloadWithURL:url delegate:delegate options:options userInfo:nil];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate options:(SDWebImageOptions)options userInfo:(NSDictionary *)userInfo
{
    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, XCode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    if ([url isKindOfClass:NSString.class])
    {
        url = [NSURL URLWithString:(NSString *)url];
    }
    else if (![url isKindOfClass:NSURL.class])
    {
        url = nil; // Prevent some common crashes due to common wrong values passed like NSNull.null for instance
    }
    
    if (!url || !delegate || (!(options & SDWebImageRetryFailed) && [failedURLs containsObject:url]))
    {
        return;
    }
    
    // Check the on-disk cache async so we don't block the main thread
    [cacheDelegates addObject:delegate];
    [cacheURLs addObject:url];
    
    NSString *cacheKey = [self cacheKeyForURL:url withOptions:options userInfo:userInfo];
    
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          delegate, @"delegate",
                          url, @"url",
                          [NSNumber numberWithInt:options], @"options",
                          userInfo ? userInfo : [NSNull null], @"userInfo",
                          nil];
    [[SDImageCache sharedImageCache] queryDiskCacheForKey:cacheKey delegate:self userInfo:info];
}

#if NS_BLOCKS_AVAILABLE
- (void)downloadWithURL:(NSURL *)url delegate:(id)delegate options:(SDWebImageOptions)options success:(SDWebImageSuccessBlock)success failure:(SDWebImageFailureBlock)failure
{
    [self downloadWithURL:url delegate:delegate options:options userInfo:nil success:success failure:failure];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id)delegate options:(SDWebImageOptions)options userInfo:(NSDictionary *)userInfo success:(SDWebImageSuccessBlock)success failure:(SDWebImageFailureBlock)failure
{
    // repeated logic from above due to requirement for backwards compatability for iOS versions without blocks
    
    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, XCode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    if ([url isKindOfClass:NSString.class])
    {
        url = [NSURL URLWithString:(NSString *)url];
    }
    
    if (!url || !delegate || (!(options & SDWebImageRetryFailed) && [failedURLs containsObject:url]))
    {
        return;
    }
    
    // Check the on-disk cache async so we don't block the main thread
    [cacheDelegates addObject:delegate];
    [cacheURLs addObject:url];
    SDWebImageSuccessBlock successCopy = [success copy];
    SDWebImageFailureBlock failureCopy = [failure copy];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          delegate, @"delegate",
                          url, @"url",
                          [NSNumber numberWithInt:options], @"options",
                          userInfo ? userInfo : [NSNull null], @"userInfo",
                          successCopy, @"success",
                          failureCopy, @"failure",
                          nil];
    SDWIRelease(successCopy);
    SDWIRelease(failureCopy);
    
    NSString *cacheKey = [self cacheKeyForURL:url withOptions:options userInfo:userInfo];
    
    [[SDImageCache sharedImageCache] queryDiskCacheForKey:cacheKey delegate:self userInfo:info];
}
#endif

- (void)cancelForDelegate:(id<SDWebImageManagerDelegate>)delegate
{
    NSUInteger idx;
    while ((idx = [cacheDelegates indexOfObjectIdenticalTo:delegate]) != NSNotFound)
    {
        [cacheDelegates removeObjectAtIndex:idx];
        [cacheURLs removeObjectAtIndex:idx];
    }
    
    while ((idx = [downloadDelegates indexOfObjectIdenticalTo:delegate]) != NSNotFound)
    {
        SDWebImageDownloader *downloader = SDWIReturnRetained([downloaders objectAtIndex:idx]);
        
        [downloadInfo removeObjectAtIndex:idx];
        [downloadDelegates removeObjectAtIndex:idx];
        [downloaders removeObjectAtIndex:idx];
        
        if (![downloaders containsObject:downloader])
        {
            // No more delegate are waiting for this download, cancel it
            [downloader cancel];
            [downloaderForURL removeObjectForKey:downloader.url];
        }
        
        SDWIRelease(downloader);
    }
}

- (void)cancelAll
{
    for (SDWebImageDownloader *downloader in downloaders)
    {
        [downloader cancel];
    }
    [cacheDelegates removeAllObjects];
    [cacheURLs removeAllObjects];
    
    [downloadInfo removeAllObjects];
    [downloadDelegates removeAllObjects];
    [downloaders removeAllObjects];
    [downloaderForURL removeAllObjects];
}

#pragma mark SDImageCacheDelegate

- (NSUInteger)indexOfDelegate:(id<SDWebImageManagerDelegate>)delegate waitingForURL:(NSURL *)url
{
    // Do a linear search, simple (even if inefficient)
    NSUInteger idx;
    for (idx = 0; idx < [cacheDelegates count]; idx++)
    {
        if ([cacheDelegates objectAtIndex:idx] == delegate && [[cacheURLs objectAtIndex:idx] isEqual:url])
        {
            return idx;
        }
    }
    return NSNotFound;
}

- (void)imageCache:(SDImageCache *)imageCache didFindImage:(UIImage *)image forKey:(NSString *)key userInfo:(NSDictionary *)info
{
    NSURL *url = [info objectForKey:@"url"];
    id<SDWebImageManagerDelegate> delegate = [info objectForKey:@"delegate"];
    
    NSUInteger idx = [self indexOfDelegate:delegate waitingForURL:url];
    if (idx == NSNotFound)
    {
        // Request has since been canceled
        return;
    }
    
    if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:)])
    {
        [delegate performSelector:@selector(webImageManager:didFinishWithImage:) withObject:self withObject:image];
    }
    if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:forURL:)])
    {
        objc_msgSend(delegate, @selector(webImageManager:didFinishWithImage:forURL:), self, image, url);
    }
    if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:forURL:userInfo:)])
    {
        NSDictionary *userInfo = [info objectForKey:@"userInfo"];
        if ([userInfo isKindOfClass:NSNull.class])
        {
            userInfo = nil;
        }
        objc_msgSend(delegate, @selector(webImageManager:didFinishWithImage:forURL:userInfo:), self, image, url, userInfo);
    }
#if NS_BLOCKS_AVAILABLE
    if ([info objectForKey:@"success"])
    {
        SDWebImageSuccessBlock success = [info objectForKey:@"success"];
        success(image, YES);
    }
#endif
    
    [cacheDelegates removeObjectAtIndex:idx];
    [cacheURLs removeObjectAtIndex:idx];
}

- (void)imageCache:(SDImageCache *)imageCache didNotFindImageForKey:(NSString *)key userInfo:(NSDictionary *)info
{
    NSURL *url = [info objectForKey:@"url"];
    id<SDWebImageManagerDelegate> delegate = [info objectForKey:@"delegate"];
    SDWebImageOptions options = [[info objectForKey:@"options"] intValue];
    
    NSUInteger idx = [self indexOfDelegate:delegate waitingForURL:url];
    if (idx == NSNotFound)
    {
        // Request has since been canceled
        return;
    }
    
    [cacheDelegates removeObjectAtIndex:idx];
    [cacheURLs removeObjectAtIndex:idx];
    
    // Share the same downloader for identical URLs so we don't download the same URL several times
    SDWebImageDownloader *downloader = [downloaderForURL objectForKey:url];
    
    if (!downloader)
    {
        downloader = [SDWebImageDownloader downloaderWithURL:url delegate:self userInfo:info lowPriority:(options & SDWebImageLowPriority)];
        [downloaderForURL setObject:downloader forKey:url];
    }
    else
    {
        // Reuse shared downloader
        downloader.lowPriority = (options & SDWebImageLowPriority);
    }
    
    if ((options & SDWebImageProgressiveDownload) && !downloader.progressive)
    {
        // Turn progressive download support on demand
        downloader.progressive = YES;
    }
    
    [downloadInfo addObject:info];
    [downloadDelegates addObject:delegate];
    [downloaders addObject:downloader];
}

#pragma mark SDWebImageDownloaderDelegate

- (void)imageDownloader:(SDWebImageDownloader *)downloader didUpdatePartialImage:(UIImage *)image
{
    // Notify all the downloadDelegates with this downloader
    for (NSInteger idx = (NSInteger)[downloaders count] - 1; idx >= 0; idx--)
    {
        NSUInteger uidx = (NSUInteger)idx;
        SDWebImageDownloader *aDownloader = [downloaders objectAtIndex:uidx];
        if (aDownloader == downloader)
        {
            id<SDWebImageManagerDelegate> delegate = [downloadDelegates objectAtIndex:uidx];
            SDWIRetain(delegate);
            SDWIAutorelease(delegate);
            
            if ([delegate respondsToSelector:@selector(webImageManager:didProgressWithPartialImage:forURL:)])
            {
                objc_msgSend(delegate, @selector(webImageManager:didProgressWithPartialImage:forURL:), self, image, downloader.url);
            }
            if ([delegate respondsToSelector:@selector(webImageManager:didProgressWithPartialImage:forURL:userInfo:)])
            {
                NSDictionary *userInfo = [[downloadInfo objectAtIndex:uidx] objectForKey:@"userInfo"];
                if ([userInfo isKindOfClass:NSNull.class])
                {
                    userInfo = nil;
                }
                objc_msgSend(delegate, @selector(webImageManager:didProgressWithPartialImage:forURL:userInfo:), self, image, downloader.url, userInfo);
            }
        }
    }
}

- (void)postProcessingImageDownloader:(SDWebImageDownloader *)downloader didFinishWithImage:(UIImage *)image
{
    SDWIRetain(downloader);
    SDWebImageOptions options = [[downloader.userInfo objectForKey:@"options"] intValue];
    
    // Notify all the downloadDelegates with this downloader
    for (NSInteger idx = (NSInteger)[downloaders count] - 1; idx >= 0; idx--)
    {
        NSUInteger uidx = (NSUInteger)idx;
        SDWebImageDownloader *aDownloader = [downloaders objectAtIndex:uidx];
        if (aDownloader == downloader)
        {
            id<SDWebImageManagerDelegate> delegate = [downloadDelegates objectAtIndex:uidx];
            SDWIRetain(delegate);
            SDWIAutorelease(delegate);
            
            if (image)
            {
                if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:)])
                {
                    [delegate performSelector:@selector(webImageManager:didFinishWithImage:) withObject:self withObject:image];
                }
                if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:forURL:)])
                {
                    objc_msgSend(delegate, @selector(webImageManager:didFinishWithImage:forURL:), self, image, downloader.url);
                }
                if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:forURL:userInfo:)])
                {
                    NSDictionary *userInfo = [[downloadInfo objectAtIndex:uidx] objectForKey:@"userInfo"];
                    if ([userInfo isKindOfClass:NSNull.class])
                    {
                        userInfo = nil;
                    }
                    objc_msgSend(delegate, @selector(webImageManager:didFinishWithImage:forURL:userInfo:), self, image, downloader.url, userInfo);
                }
#if NS_BLOCKS_AVAILABLE
                if ([[downloadInfo objectAtIndex:uidx] objectForKey:@"success"])
                {
                    SDWebImageSuccessBlock success = [[downloadInfo objectAtIndex:uidx] objectForKey:@"success"];
                    success(image, NO);
                }
#endif
            }
            else
            {
                if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:)])
                {
                    [delegate performSelector:@selector(webImageManager:didFailWithError:) withObject:self withObject:nil];
                }
                if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:forURL:)])
                {
                    objc_msgSend(delegate, @selector(webImageManager:didFailWithError:forURL:), self, nil, downloader.url);
                }
                if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:forURL:userInfo:)])
                {
                    NSDictionary *userInfo = [[downloadInfo objectAtIndex:uidx] objectForKey:@"userInfo"];
                    if ([userInfo isKindOfClass:NSNull.class])
                    {
                        userInfo = nil;
                    }
                    objc_msgSend(delegate, @selector(webImageManager:didFailWithError:forURL:userInfo:), self, nil, downloader.url, userInfo);
                }
#if NS_BLOCKS_AVAILABLE
                if ([[downloadInfo objectAtIndex:uidx] objectForKey:@"failure"])
                {
                    SDWebImageFailureBlock failure = [[downloadInfo objectAtIndex:uidx] objectForKey:@"failure"];
                    failure(nil);
                }
#endif
            }
            
            [downloaders removeObjectAtIndex:uidx];
            [downloadInfo removeObjectAtIndex:uidx];
            [downloadDelegates removeObjectAtIndex:uidx];
        }
    }
    
    if (image)
    {
        // added by smule
        // userInfo is stored in SDWebImageManager as an object under downloader's userInfo dictionary under key userInfo
        NSDictionary *userInfo = [downloader.userInfo objectForKey:@"userInfo"];
        
        // it may be NSNull class, which will crash if attempted to access. this pattern for checking is used elsewhere in this class, so use it here
        if ([userInfo isKindOfClass:NSNull.class])
        {
            userInfo = nil;
        }
        NSString *cacheKey = [self cacheKeyForURL:downloader.url withOptions:options userInfo:userInfo];
        NSData *imageData = downloader.imageData;
        
        // if we have added roundness, we need to save as PNG to preserve alpha component
        if ((options & SDWebImageCircleImageToCache))
        {
            imageData = UIImagePNGRepresentation(image);
        }
        // if we have not added roundness, but augmented size, we need ot save as JPEG
        else if ( [userInfo objectForKey:kMaxImageSizeForCacheKey] )
        {
            //CGSize size = CGSizeFromString([userInfo objectForKey:kMaxImageSizeForCacheKey]);
            // only perform if we are bigger than the desired size
            //if ( image.size.width > size.width || image.size.height > size.width )
            imageData = UIImageJPEGRepresentation(image, 0.7);
        }
        
        // Store the image in the cache
        [[SDImageCache sharedImageCache] storeImage:image
                                          imageData:imageData
                                             forKey:cacheKey
                                             toDisk:!(options & SDWebImageCacheMemoryOnly)];
    }
    else if (!(options & SDWebImageRetryFailed))
    {
        // The image can't be downloaded from this URL, mark the URL as failed so we won't try and fail again and again
        // (do this only if SDWebImageRetryFailed isn't activated)
        [failedURLs addObject:downloader.url];
    }
    
    
    // Release the downloader
    [downloaderForURL removeObjectForKey:downloader.url];
    SDWIRelease(downloader);
    
}

- (void)imageDownloader:(SDWebImageDownloader *)downloader didFinishWithImage:(UIImage *)image
{
    SDWebImageOptions options = [[downloader.userInfo objectForKey:@"options"] intValue];
    
    // hmm... not arc
    SDWebImageManager *weakself = self;
    
    // added by smule: ---------------------------------------------------------------
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        // if we have passed in an image size, we need to use it
        
        // userInfo is stored in SDWebImageManager as an object under downloader's userInfo dictionary under key userInfo
        NSDictionary *userInfo = [downloader.userInfo objectForKey:@"userInfo"];
        
        // it may be NSNull class, which will crash if attempted to access. this pattern for checking is used elsewhere in this class, so use it here
        if ([userInfo isKindOfClass:NSNull.class])
        {
            userInfo = nil;
        }
        
        UIImage *newImage = nil;
        
        NSString *newSize = [userInfo objectForKey:kMaxImageSizeForCacheKey];
        if ( newSize )
        {
            CGSize size = CGSizeFromString(newSize);
            // only perform if we are bigger than the desired max size
            //if ( image.size.width > size.width || image.size.height > size.height )
            newImage = [self resizeImage:image toSize:size interpolationQuality:kCGInterpolationHigh];
        }
        
        if (!newImage) {
            newImage = image;
        }
        
        // if we have set the circular image flag, we need to convert this image to a circle before proceeding
        if ((options & SDWebImageCircleImageToCache))
        {
            newImage = [self createCircleImageFromImage:newImage];
        }
        // -------------------------------------------------------------------------------
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakself postProcessingImageDownloader:downloader didFinishWithImage:newImage];
        });
    });
}

- (void)imageDownloader:(SDWebImageDownloader *)downloader didFailWithError:(NSError *)error;
{
    SDWIRetain(downloader);
    
    // Notify all the downloadDelegates with this downloader
    for (NSInteger idx = (NSInteger)[downloaders count] - 1; idx >= 0; idx--)
    {
        NSUInteger uidx = (NSUInteger)idx;
        SDWebImageDownloader *aDownloader = [downloaders objectAtIndex:uidx];
        if (aDownloader == downloader)
        {
            id<SDWebImageManagerDelegate> delegate = [downloadDelegates objectAtIndex:uidx];
            SDWIRetain(delegate);
            SDWIAutorelease(delegate);
            
            if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:)])
            {
                [delegate performSelector:@selector(webImageManager:didFailWithError:) withObject:self withObject:error];
            }
            if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:forURL:)])
            {
                objc_msgSend(delegate, @selector(webImageManager:didFailWithError:forURL:), self, error, downloader.url);
            }
            if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:forURL:userInfo:)])
            {
                NSDictionary *userInfo = [[downloadInfo objectAtIndex:uidx] objectForKey:@"userInfo"];
                if ([userInfo isKindOfClass:NSNull.class])
                {
                    userInfo = nil;
                }
                objc_msgSend(delegate, @selector(webImageManager:didFailWithError:forURL:userInfo:), self, error, downloader.url, userInfo);
            }
#if NS_BLOCKS_AVAILABLE
            if ([[downloadInfo objectAtIndex:uidx] objectForKey:@"failure"])
            {
                SDWebImageFailureBlock failure = [[downloadInfo objectAtIndex:uidx] objectForKey:@"failure"];
                failure(error);
            }
#endif
            
            [downloaders removeObjectAtIndex:uidx];
            [downloadInfo removeObjectAtIndex:uidx];
            [downloadDelegates removeObjectAtIndex:uidx];
        }
    }
    
    // Release the downloader
    [downloaderForURL removeObjectForKey:downloader.url];
    SDWIRelease(downloader);
}

#pragma mark - smule additions
- (UIImage*)createCircleImageFromImage:(UIImage*)image
{
    // create a circlized image
    BOOL isSquare = (image.size.height == image.size.width);
    CGFloat d = MAX(image.size.height, image.size.width);
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(d, d), NO, 0.0);
    
    CALayer *layer = [[CALayer alloc] init];
    layer.frame = CGRectMake(0, 0, d, d);
    layer.masksToBounds = YES;
    layer.rasterizationScale = [[UIScreen mainScreen] scale];
    layer.opaque = NO;
    layer.cornerRadius = d/2.0;
    layer.contents = (__bridge id)(image.CGImage);
    layer.contentsGravity = isSquare ? kCAGravityResizeAspectFill : kCAGravityCenter;
    [layer renderInContext:UIGraphicsGetCurrentContext()];
    
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return newImage;
}

- (UIImage *)resizeImage:(UIImage*)image
                  toSize:(CGSize)newSize
    interpolationQuality:(CGInterpolationQuality)quality {
    
    CGRect newRect = CGRectIntegral(CGRectMake(0, 0, newSize.width, newSize.height));
    CGImageRef imageRef = image.CGImage;
    //CGSize originalSize = image.size;
    
    // Build a context that's the same dimensions as the new size
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(NULL,
                                                (int)(newRect.size.width),
                                                (int)(newRect.size.height),
                                                8,
                                                0,
                                                space,
                                                (CGBitmapInfo)kCGImageAlphaPremultipliedLast
                                                );
    CGColorSpaceRelease(space);
    
    // Set the quality level to use when rescaling
    CGContextSetInterpolationQuality(bitmap, quality);
    
    // Draw into the context; this scales the image
    CGContextDrawImage(bitmap, newRect, imageRef);
    
    // Get the resized image from the context and a UIImage
    CGImageRef newImageRef = CGBitmapContextCreateImage(bitmap);
    UIImage *newImage = [UIImage imageWithCGImage:newImageRef];
    
    // Clean up
    CGContextRelease(bitmap);
    CGImageRelease(newImageRef);
    
    return newImage;
}

@end
