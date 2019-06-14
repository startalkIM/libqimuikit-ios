//
//  QTalkSessionDataManager.h
//  QIMUIKit
//
//  Created by qitmac000645 on 2019/5/27.
//

#import <Foundation/Foundation.h>
@class QtalkSessionModel;
NS_ASSUME_NONNULL_BEGIN

typedef void(^qtalkSessionRefreshAllDataBlock)(void);

@protocol QTalkSessionViewDataManager <NSObject>

- (void)removeItemDataFromQTalkSessionAtIndexPath:(NSIndexPath *)indexPath;

- (void)refreshCell;


@end

@interface QTalkSessionDataManager : NSObject<QTalkSessionViewDataManager>
@property (nonatomic , copy) qtalkSessionRefreshAllDataBlock qtBlock;
@property (nonatomic , weak) id<QTalkSessionViewDataManager> delegate;
@property (nonatomic , strong ,readonly) NSMutableArray * dataSource;
+ (instancetype)manager;
- (void)registCellNotification;
- (void)addDataModel:(QtalkSessionModel *)model;
- (NSMutableArray *)getSessionList;
- (void)setListWithModels:(NSMutableArray *)modelArrs;
- (id)getModelInSessionListWithIndex:(NSInteger)index;
- (void)deleteModelFromSessionListWithIndex:(NSInteger)index;
- (void)removeAllData;
@end

NS_ASSUME_NONNULL_END
