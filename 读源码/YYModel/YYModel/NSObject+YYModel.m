//
//  NSObject+YYModel.m
//  YYModel <https://github.com/ibireme/YYModel>
//
//  Created by ibireme on 15/5/10.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "NSObject+YYModel.h"
#import "YYClassInfo.h"
#import <objc/message.h>
#import <UIKit/UIKit.h>
#define force_inline __inline__ __attribute__((always_inline))

/// 不同NS类型的Type值
typedef NS_ENUM (NSUInteger, YYEncodingNSType) {
    YYEncodingTypeNSUnknown = 0,
    YYEncodingTypeNSString,
    YYEncodingTypeNSMutableString,
    YYEncodingTypeNSValue,
    YYEncodingTypeNSNumber,
    YYEncodingTypeNSDecimalNumber,
    YYEncodingTypeNSData,
    YYEncodingTypeNSMutableData,
    YYEncodingTypeNSDate,
    YYEncodingTypeNSURL,
    YYEncodingTypeNSArray,
    YYEncodingTypeNSMutableArray,
    YYEncodingTypeNSDictionary,
    YYEncodingTypeNSMutableDictionary,
    YYEncodingTypeNSSet,
    YYEncodingTypeNSMutableSet,
};

/// 从传进来的class 得到对应的Type值,先判断是否为Foundation的类
static force_inline YYEncodingNSType YYClassGetNSType(Class cls) {
    if (!cls) return YYEncodingTypeNSUnknown;
    if ([cls isSubclassOfClass:[NSMutableString class]]) return YYEncodingTypeNSMutableString;
    if ([cls isSubclassOfClass:[NSString class]]) return YYEncodingTypeNSString;
    if ([cls isSubclassOfClass:[NSDecimalNumber class]]) return YYEncodingTypeNSDecimalNumber;
    if ([cls isSubclassOfClass:[NSNumber class]]) return YYEncodingTypeNSNumber;
    if ([cls isSubclassOfClass:[NSValue class]]) return YYEncodingTypeNSValue;
    if ([cls isSubclassOfClass:[NSMutableData class]]) return YYEncodingTypeNSMutableData;
    if ([cls isSubclassOfClass:[NSData class]]) return YYEncodingTypeNSData;
    if ([cls isSubclassOfClass:[NSDate class]]) return YYEncodingTypeNSDate;
    if ([cls isSubclassOfClass:[NSURL class]]) return YYEncodingTypeNSURL;
    if ([cls isSubclassOfClass:[NSMutableArray class]]) return YYEncodingTypeNSMutableArray;
    if ([cls isSubclassOfClass:[NSArray class]]) return YYEncodingTypeNSArray;
    if ([cls isSubclassOfClass:[NSMutableDictionary class]]) return YYEncodingTypeNSMutableDictionary;
    if ([cls isSubclassOfClass:[NSDictionary class]]) return YYEncodingTypeNSDictionary;
    if ([cls isSubclassOfClass:[NSMutableSet class]]) return YYEncodingTypeNSMutableSet;
    if ([cls isSubclassOfClass:[NSSet class]]) return YYEncodingTypeNSSet;
    return YYEncodingTypeNSUnknown;
}

/// C 类型下的处理
static force_inline BOOL YYEncodingTypeIsCNumber(YYEncodingType type) {
    switch (type & YYEncodingTypeMask) {
        case YYEncodingTypeBool:
        case YYEncodingTypeInt8:
        case YYEncodingTypeUInt8:
        case YYEncodingTypeInt16:
        case YYEncodingTypeUInt16:
        case YYEncodingTypeInt32:
        case YYEncodingTypeUInt32:
        case YYEncodingTypeInt64:
        case YYEncodingTypeUInt64:
        case YYEncodingTypeFloat:
        case YYEncodingTypeDouble:
        case YYEncodingTypeLongDouble: return YES;
        default: return NO;
    }
}

/// 从一个id类型中 解析初NSNumber
static force_inline NSNumber *YYNSNumberCreateFromID(__unsafe_unretained id value) {
    static NSCharacterSet *dot;
    static NSDictionary *dic;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ // 单例 这个映射表只生成一次
        dot = [NSCharacterSet characterSetWithRange:NSMakeRange('.', 1)];
        dic = @{@"TRUE" :   @(YES),
                @"True" :   @(YES),
                @"true" :   @(YES),
                @"FALSE" :  @(NO),
                @"False" :  @(NO),
                @"false" :  @(NO),
                @"YES" :    @(YES),
                @"Yes" :    @(YES),
                @"yes" :    @(YES),
                @"NO" :     @(NO),
                @"No" :     @(NO),
                @"no" :     @(NO),
                @"NIL" :    (id)kCFNull,
                @"Nil" :    (id)kCFNull,
                @"nil" :    (id)kCFNull,
                @"NULL" :   (id)kCFNull,
                @"Null" :   (id)kCFNull,
                @"null" :   (id)kCFNull,
                @"(NULL)" : (id)kCFNull,
                @"(Null)" : (id)kCFNull,
                @"(null)" : (id)kCFNull,
                @"<NULL>" : (id)kCFNull,
                @"<Null>" : (id)kCFNull,
                @"<null>" : (id)kCFNull};
    });
    
    if (!value || value == (id)kCFNull) return nil;
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSNumber *num = dic[value];
        if (num) {
            if (num == (id)kCFNull) return nil;
            return num;
        }
        if ([(NSString *)value rangeOfCharacterFromSet:dot].location != NSNotFound) {
            const char *cstring = ((NSString *)value).UTF8String;
            if (!cstring) return nil;
            double num = atof(cstring);
            if (isnan(num) || isinf(num)) return nil;
            return @(num);
        } else {
            const char *cstring = ((NSString *)value).UTF8String;
            if (!cstring) return nil;
            return @(atoll(cstring));
        }
    }
    return nil;
}

/// 将NSSTRING类型转为NSDate类型
static force_inline NSDate *YYNSDateFromString(__unsafe_unretained NSString *string) {
    typedef NSDate* (^YYNSDateParseBlock)(NSString *string);
    #define kParserNum 34
    static YYNSDateParseBlock blocks[kParserNum + 1] = {0};
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter.dateFormat = @"yyyy-MM-dd";
            blocks[10] = ^(NSString *string) { return [formatter dateFromString:string]; };
        }
        
        {
            NSDateFormatter *formatter1 = [[NSDateFormatter alloc] init];
            formatter1.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter1.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter1.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
            
            NSDateFormatter *formatter2 = [[NSDateFormatter alloc] init];
            formatter2.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter2.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter2.dateFormat = @"yyyy-MM-dd HH:mm:ss";

            NSDateFormatter *formatter3 = [[NSDateFormatter alloc] init];
            formatter3.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter3.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter3.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS";

            NSDateFormatter *formatter4 = [[NSDateFormatter alloc] init];
            formatter4.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter4.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter4.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
            
            blocks[19] = ^(NSString *string) {
                if ([string characterAtIndex:10] == 'T') {
                    return [formatter1 dateFromString:string];
                } else {
                    return [formatter2 dateFromString:string];
                }
            };

            blocks[23] = ^(NSString *string) {
                if ([string characterAtIndex:10] == 'T') {
                    return [formatter3 dateFromString:string];
                } else {
                    return [formatter4 dateFromString:string];
                }
            };
        }
        
        {

            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";

            NSDateFormatter *formatter2 = [NSDateFormatter new];
            formatter2.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter2.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";

            blocks[20] = ^(NSString *string) { return [formatter dateFromString:string]; };
            blocks[24] = ^(NSString *string) { return [formatter dateFromString:string]?: [formatter2 dateFromString:string]; };
            blocks[25] = ^(NSString *string) { return [formatter dateFromString:string]; };
            blocks[28] = ^(NSString *string) { return [formatter2 dateFromString:string]; };
            blocks[29] = ^(NSString *string) { return [formatter2 dateFromString:string]; };
        }
        
        {

            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.dateFormat = @"EEE MMM dd HH:mm:ss Z yyyy";

            NSDateFormatter *formatter2 = [NSDateFormatter new];
            formatter2.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter2.dateFormat = @"EEE MMM dd HH:mm:ss.SSS Z yyyy";

            blocks[30] = ^(NSString *string) { return [formatter dateFromString:string]; };
            blocks[34] = ^(NSString *string) { return [formatter2 dateFromString:string]; };
        }
    });
    if (!string) return nil;
    if (string.length > kParserNum) return nil;
    YYNSDateParseBlock parser = blocks[string.length];
    if (!parser) return nil;
    return parser(string);
    #undef kParserNum
}


/// 取得block的类
static force_inline Class YYNSBlockClass() {
    static Class cls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void (^block)(void) = ^{};
        cls = ((NSObject *)block).class;
        while (class_getSuperclass(cls) != [NSObject class]) {
            cls = class_getSuperclass(cls);
        }
    });
    return cls; // current is "NSBlock"
}



/**
 将NSDate转成ISO标准格式
 */
static force_inline NSDateFormatter *YYISODateFormatter() {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    });
    return formatter;
}

/// 通过keyPaths 从 dict中取得对应的value
static force_inline id YYValueForKeyPath(__unsafe_unretained NSDictionary *dic, __unsafe_unretained NSArray *keyPaths) {
    id value = nil;
    for (NSUInteger i = 0, max = keyPaths.count; i < max; i++) {
        value = dic[keyPaths[i]];
        if (i + 1 < max) {
            if ([value isKindOfClass:[NSDictionary class]]) {
                dic = value;
            } else {
                return nil;
            }
        }
    }
    return value;
}

// 从Dic中获得对应key的值
static force_inline id YYValueForMultiKeys(__unsafe_unretained NSDictionary *dic, __unsafe_unretained NSArray *multiKeys) {
    id value = nil;
    for (NSString *key in multiKeys) {
        if ([key isKindOfClass:[NSString class]]) {
            value = dic[key];
            if (value) break;
        } else {
            value = YYValueForKeyPath(dic, (NSArray *)key);
            if (value) break;
        }
    }
    return value;
}

// 创建YYModelProperty的元类
@interface _YYModelPropertyMeta : NSObject {
    @package
    // property 名
    NSString *_name;
    // property 编码
    YYEncodingType _type;
    // Foundation类型
    YYEncodingNSType _nsType;
    // 是否为基础数据类型
    BOOL _isCNumber;
    // Class
    Class _cls;
    // 是否为集合类型即Array／Set／Dicitinoary
    Class _genericCls;
    // 属性的get方法和set方法
    SEL _getter;
    SEL _setter;
    // 属性是否提供KVC方法
    BOOL _isKVCCompatible;
    // 属性是否支持归档
    BOOL _isStructAvailableForKeyedArchiver;
    // 是否有自定义的映射字典
    BOOL _hasCustomClassFromDictionary;
    
    // json 与属性映射的key 如 @{@"name":@"user"}
    NSString *_mappedToKey;
    // json 与属性映射的key是一个路径 @{@"name":@"person.name"}
    NSArray *_mappedToKeyPath;
    // json 与属性映射的key是一个数组,即一个key对应多个json key @{@"name":@[@"name",@"user",@"account"]}
    NSArray *_mappedToKeyArray;
    // 描述的property
    YYClassPropertyInfo *_info;
    // 在多个属性映射一个json key 的时候使用
    _YYModelPropertyMeta *_next;
}
@end

@implementation _YYModelPropertyMeta
+ (instancetype)metaWithClassInfo:(YYClassInfo *)classInfo propertyInfo:(YYClassPropertyInfo *)propertyInfo generic:(Class)generic {
    // 创建一个meta对象
    _YYModelPropertyMeta *meta = [self new];
    // 将属性名赋值
    meta->_name = propertyInfo.name;
    // 赋值编码类型
    meta->_type = propertyInfo.type;
    // 将描述属性赋值
    meta->_info = propertyInfo;
    // 记录属性为容器类型的时候 元素的映射类型
    meta->_genericCls = generic;
    
    if ((meta->_type & YYEncodingTypeMask) == YYEncodingTypeObject) { // 先匹配是否为NS类型 即Foundation 类型
        meta->_nsType = YYClassGetNSType(propertyInfo.cls);
    } else { // 是否为C数据类型
        meta->_isCNumber = YYEncodingTypeIsCNumber(meta->_type);
    }
    
    // 属性为结构体类型
    if ((meta->_type & YYEncodingTypeMask) == YYEncodingTypeStruct) {
        /*
         It seems that NSKeyedUnarchiver cannot decode NSValue except these structs:
         */
        static NSSet *types = nil;
        static dispatch_once_t onceToken;
        // 单例 创建一份c结构体类型映射
        dispatch_once(&onceToken, ^{
            NSMutableSet *set = [NSMutableSet new];
            // 32 bit
            [set addObject:@"{CGSize=ff}"];
            [set addObject:@"{CGPoint=ff}"];
            [set addObject:@"{CGRect={CGPoint=ff}{CGSize=ff}}"];
            [set addObject:@"{CGAffineTransform=ffffff}"];
            [set addObject:@"{UIEdgeInsets=ffff}"];
            [set addObject:@"{UIOffset=ff}"];
            // 64 bit
            [set addObject:@"{CGSize=dd}"];
            [set addObject:@"{CGPoint=dd}"];
            [set addObject:@"{CGRect={CGPoint=dd}{CGSize=dd}}"];
            [set addObject:@"{CGAffineTransform=dddddd}"];
            [set addObject:@"{UIEdgeInsets=dddd}"];
            [set addObject:@"{UIOffset=dd}"];
            types = set;
        });
        
        // 只有以上的结构体才能被归档
        if ([types containsObject:propertyInfo.typeEncoding]) {
            meta->_isStructAvailableForKeyedArchiver = YES;
        }
    }
    // 设置class类型
    meta->_cls = propertyInfo.cls;
    
    // 如果是容器类型
    if (generic) {
        // 从容器class 中读取
        meta->_hasCustomClassFromDictionary = [generic respondsToSelector:@selector(modelCustomClassForDictionary:)];
    } else if (meta->_cls && meta->_nsType == YYEncodingTypeNSUnknown) {
        // 从class类型中读取
        meta->_hasCustomClassFromDictionary = [meta->_cls respondsToSelector:@selector(modelCustomClassForDictionary:)];
    }
    
    // getter 和 setter 方法
    if (propertyInfo.getter) {
        if ([classInfo.cls instancesRespondToSelector:propertyInfo.getter]) {
            meta->_getter = propertyInfo.getter;
        }
    }
    if (propertyInfo.setter) {
        if ([classInfo.cls instancesRespondToSelector:propertyInfo.setter]) {
            meta->_setter = propertyInfo.setter;
        }
    }
    
    /**
     *  只有实现了getter和setter方法 才能实现归档
     */
    if (meta->_getter && meta->_setter) {
        /*
         KVC中不支持的类型
         long double
         指针对象 SEL等
         */
        switch (meta->_type & YYEncodingTypeMask) {
            case YYEncodingTypeBool:
            case YYEncodingTypeInt8:
            case YYEncodingTypeUInt8:
            case YYEncodingTypeInt16:
            case YYEncodingTypeUInt16:
            case YYEncodingTypeInt32:
            case YYEncodingTypeUInt32:
            case YYEncodingTypeInt64:
            case YYEncodingTypeUInt64:
            case YYEncodingTypeFloat:
            case YYEncodingTypeDouble:
            case YYEncodingTypeObject:
            case YYEncodingTypeClass:
            case YYEncodingTypeBlock:
            case YYEncodingTypeStruct:
            case YYEncodingTypeUnion: {
                meta->_isKVCCompatible = YES;
            } break;
            default: break;
        }
    }
    
    return meta;
}
@end


/// YYModelMeta 对ClassInfo增加描述
@interface _YYModelMeta : NSObject {
    @package
    YYClassInfo *_classInfo;

    // json key 和 property Meta 的映射关系字典
    NSDictionary *_mapper;

    // 所有属性的propertyMeta
    NSArray *_allPropertyMetas;

    // 映射jsonkeyPath 的PropertyMetas
    NSArray *_keyPathPropertyMetas;
    
    // 映射多个jsonKey的propertyMeta
    NSArray *_multiKeysPropertyMetas;
    /// 需要映射的属性的总个数
    NSUInteger _keyMappedCount;
    /// Model对应的Foundation class类型
    YYEncodingNSType _nsType;
    // 是否实现了自定义的映射关系表 这里之前已经解释过 就不再赘述
    BOOL _hasCustomWillTransformFromDictionary;
    BOOL _hasCustomTransformFromDictionary;
    BOOL _hasCustomTransformToDictionary;
    BOOL _hasCustomClassFromDictionary;
}
@end

@implementation _YYModelMeta
- (instancetype)initWithClass:(Class)cls {
    // 创建classInfo对象
    YYClassInfo *classInfo = [YYClassInfo classInfoWithClass:cls];
    // 1. 判断是否合法
    if (!classInfo) return nil;
    self = [super init];
    
    // 2. 获得黑名单
    NSSet *blacklist = nil;
    if ([cls respondsToSelector:@selector(modelPropertyBlacklist)]) {
        NSArray *properties = [(id<YYModel>)cls modelPropertyBlacklist];
        if (properties) {
            blacklist = [NSSet setWithArray:properties];
        }
    }
    
    // 3. 获得白名单
    NSSet *whitelist = nil;
    if ([cls respondsToSelector:@selector(modelPropertyWhitelist)]) {
        NSArray *properties = [(id<YYModel>)cls modelPropertyWhitelist];
        if (properties) {
            whitelist = [NSSet setWithArray:properties];
        }
    }
    
    // 4. 获取容器属性中的映射关系字典
    NSDictionary *genericMapper = nil;
    if ([cls respondsToSelector:@selector(modelContainerPropertyGenericClass)]) {// 判断类中是否实现了对应的modelContainerPropertyGenericClass方法
        /* 例如
        @{@"shadows" : [YYShadow class],
        @"borders" : YYBorder.class,
        @"attachments" : @"YYAttachment" };
        */
        genericMapper = [(id<YYModel>)cls modelContainerPropertyGenericClass];
        if (genericMapper) {
            // 将字段名和对应的class存放在字典里
            NSMutableDictionary *tmp = [NSMutableDictionary new];
            [genericMapper enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if (![key isKindOfClass:[NSString class]]) return;
                Class meta = object_getClass(obj);
                if (!meta) return;
                if (class_isMetaClass(meta)) {
                    tmp[key] = obj;
                } else if ([obj isKindOfClass:[NSString class]]) {
                    Class cls = NSClassFromString(obj);
                    if (cls) {
                        tmp[key] = cls;
                    }
                }
            }];
            genericMapper = tmp;
        }
    }
    
    // 5. 创建Class中 所有属性的PropertyMeta对象 加入到字典中
    // 用来保存class 和其父类的所有属性 除了NSOject外
    NSMutableDictionary *allPropertyMetas = [NSMutableDictionary new];
    YYClassInfo *curClassInfo = classInfo;
    while (curClassInfo && curClassInfo.superCls != nil) { // recursive parse super class, but ignore root class (NSObject/NSProxy)
        // 遍历当前ClassInfo 中的所有PropertyInfo， 将它们封装成PropertyMeta
        for (YYClassPropertyInfo *propertyInfo in curClassInfo.propertyInfos.allValues) {
            // 检查是否合法和黑名单白名单
            if (!propertyInfo.name) continue;
            if (blacklist && [blacklist containsObject:propertyInfo.name]) continue;
            if (whitelist && ![whitelist containsObject:propertyInfo.name]) continue;
            
            // 通过propetyInfo来创建一个meta对象
            _YYModelPropertyMeta *meta = [_YYModelPropertyMeta metaWithClassInfo:classInfo
                                                                    propertyInfo:propertyInfo
                                                                         generic:genericMapper[propertyInfo.name]];
            // meta nanme必须非空
            if (!meta || !meta->_name) continue;
            // 必须实现get方法和set方法
            if (!meta->_getter || !meta->_setter) continue;
            // 字典中没有这个字段 避免重复操作
            if (allPropertyMetas[meta->_name]) continue;
            allPropertyMetas[meta->_name] = meta;
        }
        // 遍历父类的property
        curClassInfo = curClassInfo.superClassInfo;
    }
    // 判断是否为空，不为空赋值给model声明中的_allPropertyMetas
    if (allPropertyMetas.count) _allPropertyMetas = allPropertyMetas.allValues.copy;
    
    // 创建映射关系 jsonkey ：propertyMeta
    NSMutableDictionary *mapper = [NSMutableDictionary new];
    NSMutableArray *keyPathPropertyMetas = [NSMutableArray new];
    NSMutableArray *multiKeysPropertyMetas = [NSMutableArray new];
    
    // 是否实现自定义的映射表
    if ([cls respondsToSelector:@selector(modelCustomPropertyMapper)]) {
        // 获得自定义的映射表
        NSDictionary *customMapper = [(id <YYModel>)cls modelCustomPropertyMapper];
        
        // 遍历自定义的字典
        [customMapper enumerateKeysAndObjectsUsingBlock:^(NSString *propertyName, NSString *mappedToKey, BOOL *stop) {
            // 创建propetyMeta
            _YYModelPropertyMeta *propertyMeta = allPropertyMetas[propertyName];
            if (!propertyMeta) return;
            // 由于用户自定义映射，把原来映射的规则删除
            [allPropertyMetas removeObjectForKey:propertyName];
            
            if ([mappedToKey isKindOfClass:[NSString class]]) { // 判断key字段是否为非空NSString
                if (mappedToKey.length == 0) return;
                // 直接保存property映射的key
                propertyMeta->_mappedToKey = mappedToKey;
                // 如果是keyPath的情况， 用数组来处理
                NSArray *keyPath = [mappedToKey componentsSeparatedByString:@"."];
                
                // {@"name":@"user.name"} => name : @[@"user",@"name"]
                if (keyPath.count > 1) {
                    // 保存keyPath映射关系
                    propertyMeta->_mappedToKeyPath = keyPath;
                    // 添加到keyPathPropertyMetas数组中
                    [keyPathPropertyMetas addObject:propertyMeta];
                }
                
                // 多个属性的时候，用next指针来指向前一个jsonKey映射的meta
                propertyMeta->_next = mapper[mappedToKey] ?: nil;
                // 保存jsonKey映射到最新的meta对象
                mapper[mappedToKey] = propertyMeta;
                
            } else if ([mappedToKey isKindOfClass:[NSArray class]]) { // 如果是数组 属于一个属性映射多个jsonKey
                
                NSMutableArray *mappedToKeyArray = [NSMutableArray new];
                for (NSString *oneKey in ((NSArray *)mappedToKey)) {
                    if (![oneKey isKindOfClass:[NSString class]]) continue;
                    if (oneKey.length == 0) continue;
                    
                    NSArray *keyPath = [oneKey componentsSeparatedByString:@"."];
                    if (keyPath.count > 1) {
                        [mappedToKeyArray addObject:keyPath];
                    } else {
                        [mappedToKeyArray addObject:oneKey];
                    }
                    
                    if (!propertyMeta->_mappedToKey) {
                        propertyMeta->_mappedToKey = oneKey;
                        propertyMeta->_mappedToKeyPath = keyPath.count > 1 ? keyPath : nil;
                    }
                }
                if (!propertyMeta->_mappedToKey) return;
                
                propertyMeta->_mappedToKeyArray = mappedToKeyArray;
                [multiKeysPropertyMetas addObject:propertyMeta];
                
                propertyMeta->_next = mapper[mappedToKey] ?: nil;
                mapper[mappedToKey] = propertyMeta;
            }
        }];
    }
    
    // 处理没有自定义映射规则的属性
    // 在上面的处理中 从allPropertyMetas中删除了有自定义映射规则的meta
    // 剩下来的是没有自定义规则的属性，在这里就让这些属性的mappedKey等于属性名
    [allPropertyMetas enumerateKeysAndObjectsUsingBlock:^(NSString *name, _YYModelPropertyMeta *propertyMeta, BOOL *stop) {
        // 直接让mappedKey等于属性名
        propertyMeta->_mappedToKey = name;
        propertyMeta->_next = mapper[name] ?: nil;
        mapper[name] = propertyMeta;
    }];
    
    // 对映射的数据做修正处理
    if (mapper.count) _mapper = mapper;
    if (keyPathPropertyMetas) _keyPathPropertyMetas = keyPathPropertyMetas;
    if (multiKeysPropertyMetas) _multiKeysPropertyMetas = multiKeysPropertyMetas;

    _classInfo = classInfo;
    _keyMappedCount = _allPropertyMetas.count;
    _nsType = YYClassGetNSType(cls);
    _hasCustomWillTransformFromDictionary = ([cls instancesRespondToSelector:@selector(modelCustomWillTransformFromDictionary:)]);
    _hasCustomTransformFromDictionary = ([cls instancesRespondToSelector:@selector(modelCustomTransformFromDictionary:)]);
    _hasCustomTransformToDictionary = ([cls instancesRespondToSelector:@selector(modelCustomTransformToDictionary:)]);
    _hasCustomClassFromDictionary = ([cls respondsToSelector:@selector(modelCustomClassForDictionary:)]);
    
    return self;
}

/// 缓存优化class对应的ClassMeta
+ (instancetype)metaWithClass:(Class)cls {
    // cls 为空
    if (!cls) return nil;
    
    // 单例的CFMutableDictionary字典， 用来缓存ClassMeta
    static CFMutableDictionaryRef cache;
    static dispatch_once_t onceToken;
    static dispatch_semaphore_t lock;
    dispatch_once(&onceToken, ^{
        cache = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        lock = dispatch_semaphore_create(1);
    });
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
    
    // 先从缓存中尝试获取
    _YYModelMeta *meta = CFDictionaryGetValue(cache, (__bridge const void *)(cls));
    dispatch_semaphore_signal(lock);
    
    // 如果没有缓存过 则需要重写建立
    if (!meta || meta->_classInfo.needUpdate) {
        meta = [[_YYModelMeta alloc] initWithClass:cls];
        if (meta) { // 将创建好的meta存入字典
            dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
            // 对cls对应的meta进行缓存处理
            CFDictionarySetValue(cache, (__bridge const void *)(cls), (__bridge const void *)(meta));
            dispatch_semaphore_signal(lock);
        }
    }
    return meta;
}

@end


/**
 根据property的类型来对值转化为NSNumber对象
 根据meta的类型，获取对应的getter方法
 1. 通过getter方法 调用objc_msgSend获得属性值
 2. 将value转化成NSNumber
 */
static force_inline NSNumber *ModelCreateNumberFromProperty(__unsafe_unretained id model,
                                                            __unsafe_unretained _YYModelPropertyMeta *meta) {
    switch (meta->_type & YYEncodingTypeMask) { // 判断类型是否为number
        case YYEncodingTypeBool: { // 用objc_msgSend调用getter方法获得value
            return @(((bool (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeInt8: {
            return @(((int8_t (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeUInt8: {
            return @(((uint8_t (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeInt16: {
            return @(((int16_t (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeUInt16: {
            return @(((uint16_t (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeInt32: {
            return @(((int32_t (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeUInt32: {
            return @(((uint32_t (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeInt64: {
            return @(((int64_t (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeUInt64: {
            return @(((uint64_t (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter));
        }
        case YYEncodingTypeFloat: {
            float num = ((float (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter);
            if (isnan(num) || isinf(num)) return nil;
            return @(num);
        }
        case YYEncodingTypeDouble: {
            double num = ((double (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter);
            if (isnan(num) || isinf(num)) return nil;
            return @(num);
        }
        case YYEncodingTypeLongDouble: {
            double num = ((long double (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter);
            if (isnan(num) || isinf(num)) return nil;
            return @(num);
        }
        default: return nil;
    }
}

/**
 1. 先将基本数据类型转化成NSNumber的num参数
 2. 通过setter方法，将转化后的num赋值给property
 */
static force_inline void ModelSetNumberToProperty(__unsafe_unretained id model,
                                                  __unsafe_unretained NSNumber *num,
                                                  __unsafe_unretained _YYModelPropertyMeta *meta) {
    switch (meta->_type & YYEncodingTypeMask) { // 判断类型
        case YYEncodingTypeBool: { // 通过setter方法赋值
            ((void (*)(id, SEL, bool))(void *) objc_msgSend)((id)model, meta->_setter, num.boolValue);
        } break;
        case YYEncodingTypeInt8: {
            ((void (*)(id, SEL, int8_t))(void *) objc_msgSend)((id)model, meta->_setter, (int8_t)num.charValue);
        } break;
        case YYEncodingTypeUInt8: {
            ((void (*)(id, SEL, uint8_t))(void *) objc_msgSend)((id)model, meta->_setter, (uint8_t)num.unsignedCharValue);
        } break;
        case YYEncodingTypeInt16: {
            ((void (*)(id, SEL, int16_t))(void *) objc_msgSend)((id)model, meta->_setter, (int16_t)num.shortValue);
        } break;
        case YYEncodingTypeUInt16: {
            ((void (*)(id, SEL, uint16_t))(void *) objc_msgSend)((id)model, meta->_setter, (uint16_t)num.unsignedShortValue);
        } break;
        case YYEncodingTypeInt32: {
            ((void (*)(id, SEL, int32_t))(void *) objc_msgSend)((id)model, meta->_setter, (int32_t)num.intValue);
        }
        case YYEncodingTypeUInt32: {
            ((void (*)(id, SEL, uint32_t))(void *) objc_msgSend)((id)model, meta->_setter, (uint32_t)num.unsignedIntValue);
        } break;
        case YYEncodingTypeInt64: {
            if ([num isKindOfClass:[NSDecimalNumber class]]) {
                ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)model, meta->_setter, (int64_t)num.stringValue.longLongValue);
            } else {
                ((void (*)(id, SEL, uint64_t))(void *) objc_msgSend)((id)model, meta->_setter, (uint64_t)num.longLongValue);
            }
        } break;
        case YYEncodingTypeUInt64: {
            if ([num isKindOfClass:[NSDecimalNumber class]]) {
                ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)model, meta->_setter, (int64_t)num.stringValue.longLongValue);
            } else {
                ((void (*)(id, SEL, uint64_t))(void *) objc_msgSend)((id)model, meta->_setter, (uint64_t)num.unsignedLongLongValue);
            }
        } break;
        case YYEncodingTypeFloat: {
            float f = num.floatValue;
            if (isnan(f) || isinf(f)) f = 0;
            ((void (*)(id, SEL, float))(void *) objc_msgSend)((id)model, meta->_setter, f);
        } break;
        case YYEncodingTypeDouble: {
            double d = num.doubleValue;
            if (isnan(d) || isinf(d)) d = 0;
            ((void (*)(id, SEL, double))(void *) objc_msgSend)((id)model, meta->_setter, d);
        } break;
        case YYEncodingTypeLongDouble: {
            long double d = num.doubleValue;
            if (isnan(d) || isinf(d)) d = 0;
            ((void (*)(id, SEL, long double))(void *) objc_msgSend)((id)model, meta->_setter, (long double)d);
        } // break; commented for code coverage in next line
        default: break;
    }
}

/**
 为property赋值：大多数是通过setter方法来实现，为什么说是大部分，因为C struct、Union、CArray是用KVC来实现的
 */
static void ModelSetValueForProperty(__unsafe_unretained id model,
                                     __unsafe_unretained id value,
                                     __unsafe_unretained _YYModelPropertyMeta *meta) {
    if (meta->_isCNumber) { // 如果是C基础数据类型 就转化成num进行赋值
        
        // 1. 把value转化成NSNumber
        NSNumber *num = YYNSNumberCreateFromID(value);
        // 2. 设置value
        ModelSetNumberToProperty(model, num, meta);
        if (num) [num class]; // 持有num的class？？
    } else if (meta->_nsType) { // 如果是NSFoundation类型
        if (value == (id)kCFNull) { // 如果是空 赋值为nil
            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, (id)nil);
        } else {
            switch (meta->_nsType) { // 判断NSType
                    // NSString类型和NSMutableString用一样的方式处理
                case YYEncodingTypeNSString:
                case YYEncodingTypeNSMutableString: {
                    if ([value isKindOfClass:[NSString class]]) {
                        if (meta->_nsType == YYEncodingTypeNSString) {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, value);
                        } else {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, ((NSString *)value).mutableCopy);
                        }
                    } else if ([value isKindOfClass:[NSNumber class]]) { // 将NSNumber转为NSString
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model,
                                                                       meta->_setter,
                                                                       (meta->_nsType == YYEncodingTypeNSString) ?
                                                                       ((NSNumber *)value).stringValue :
                                                                       ((NSNumber *)value).stringValue.mutableCopy);
                    } else if ([value isKindOfClass:[NSData class]]) { // NSData 转化成NSString
                        NSMutableString *string = [[NSMutableString alloc] initWithData:value encoding:NSUTF8StringEncoding];
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, string);
                    } else if ([value isKindOfClass:[NSURL class]]) { // NSUrl 转为NSString
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model,
                                                                       meta->_setter,
                                                                       (meta->_nsType == YYEncodingTypeNSString) ?
                                                                       ((NSURL *)value).absoluteString :
                                                                       ((NSURL *)value).absoluteString.mutableCopy);
                    } else if ([value isKindOfClass:[NSAttributedString class]]) { // NSAttributedString转为NSString
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model,
                                                                       meta->_setter,
                                                                       (meta->_nsType == YYEncodingTypeNSString) ?
                                                                       ((NSAttributedString *)value).string :
                                                                       ((NSAttributedString *)value).string.mutableCopy);
                    }
                } break;
                    // 属性类型为NSValue，NSNumber，NSDecimalNumber
                case YYEncodingTypeNSValue:
                case YYEncodingTypeNSNumber:
                case YYEncodingTypeNSDecimalNumber: {
                    if (meta->_nsType == YYEncodingTypeNSNumber) { // NSNumber 直接调用YYNSNumberCreateFromID转
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, YYNSNumberCreateFromID(value));
                    } else if (meta->_nsType == YYEncodingTypeNSDecimalNumber) { // 如果是YYEncodingTypeNSDecimalNumber
                        if ([value isKindOfClass:[NSDecimalNumber class]]) { // NSDecimalNumber
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, value);
                        } else if ([value isKindOfClass:[NSNumber class]]) { // NSNumber => NSDecimalNumber
                            NSDecimalNumber *decNum = [NSDecimalNumber decimalNumberWithDecimal:[((NSNumber *)value) decimalValue]];
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, decNum);
                        } else if ([value isKindOfClass:[NSString class]]) { // NSString => NSDecimalNumber
                            NSDecimalNumber *decNum = [NSDecimalNumber decimalNumberWithString:value];
                            NSDecimal dec = decNum.decimalValue;
                            if (dec._length == 0 && dec._isNegative) {
                                decNum = nil; // NaN
                            }
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, decNum);
                        }
                    } else { // NSValue
                        if ([value isKindOfClass:[NSValue class]]) {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, value);
                        }
                    }
                } break;
                    
                case YYEncodingTypeNSData:
                case YYEncodingTypeNSMutableData: { // NSData 和 NSMutableData类型
                    if ([value isKindOfClass:[NSData class]]) { // value 为data
                        if (meta->_nsType == YYEncodingTypeNSData) {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, value);
                        } else {
                            NSMutableData *data = ((NSData *)value).mutableCopy;
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, data);
                        }
                    } else if ([value isKindOfClass:[NSString class]]) { // NSString=>NSData
                        NSData *data = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
                        if (meta->_nsType == YYEncodingTypeNSMutableData) {
                            data = ((NSData *)data).mutableCopy;
                        }
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, data);
                    }
                } break;
                    
                case YYEncodingTypeNSDate: { // NSDate
                    if ([value isKindOfClass:[NSDate class]]) {
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, value);
                    } else if ([value isKindOfClass:[NSString class]]) { // NString 调用YYNSDateFromString转为Date类型
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, YYNSDateFromString(value));
                    }
                } break;
                    
                case YYEncodingTypeNSURL: { // NSUrl
                    if ([value isKindOfClass:[NSURL class]]) {
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, value);
                    } else if ([value isKindOfClass:[NSString class]]) {
                        NSCharacterSet *set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
                        NSString *str = [value stringByTrimmingCharactersInSet:set];
                        if (str.length == 0) {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, nil);
                        } else {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, [[NSURL alloc] initWithString:str]);
                        }
                    }
                } break;
                    
                case YYEncodingTypeNSArray:
                case YYEncodingTypeNSMutableArray: { // NSArray NSMutableArray
                    if (meta->_genericCls) { // meta是集合类型
                        NSArray *valueArr = nil;
                        if ([value isKindOfClass:[NSArray class]]) valueArr = value;
                        else if ([value isKindOfClass:[NSSet class]]) valueArr = ((NSSet *)value).allObjects;
                        if (valueArr) {
                            NSMutableArray *objectArr = [NSMutableArray new];
                            // 遍历数组
                            for (id one in valueArr) {
                                // 如果是支持的类型
                                if ([one isKindOfClass:meta->_genericCls]) {
                                    // 数组中元素的CLass 是映射对应的class
                                    [objectArr addObject:one];
                                } else if ([one isKindOfClass:[NSDictionary class]]) {
                                    Class cls = meta->_genericCls;
                                    if (meta->_hasCustomClassFromDictionary) {
                                        // 用字定义的映射表来修正映射
                                        cls = [cls modelCustomClassForDictionary:one];
                                        // 获取属性对应映射的Class
                                        if (!cls) cls = meta->_genericCls;
                                    }
                                    // 没有设置的话就直接new一个对象
                                    NSObject *newOne = [cls new];
                                    // 通过dicitionary来设置model的属性
                                    [newOne yy_modelSetWithDictionary:one];
                                    if (newOne) [objectArr addObject:newOne];
                                }
                            }
                            // 将转换好的数组赋值
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, objectArr);
                        }
                    } else {
                        // 没有设置数组内对应元素的class类型 则直接赋值
                        if ([value isKindOfClass:[NSArray class]]) {
                            if (meta->_nsType == YYEncodingTypeNSArray) {
                                ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, value);
                            } else {
                                ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model,
                                                                               meta->_setter,
                                                                               ((NSArray *)value).mutableCopy);
                            }
                        } else if ([value isKindOfClass:[NSSet class]]) {
                            if (meta->_nsType == YYEncodingTypeNSArray) {
                                ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, ((NSSet *)value).allObjects);
                            } else {
                                ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model,
                                                                               meta->_setter,
                                                                               ((NSSet *)value).allObjects.mutableCopy);
                            }
                        }
                    }
                } break;
                    
                case YYEncodingTypeNSDictionary:
                case YYEncodingTypeNSMutableDictionary: { // NSDictionary类型
                    if ([value isKindOfClass:[NSDictionary class]]) {
                        if (meta->_genericCls) { // 是否有实现容器内属性的映射类
                            NSMutableDictionary *dic = [NSMutableDictionary new];
                            [((NSDictionary *)value) enumerateKeysAndObjectsUsingBlock:^(NSString *oneKey, id oneValue, BOOL *stop) {
                                if ([oneValue isKindOfClass:[NSDictionary class]]) {
                                    Class cls = meta->_genericCls; // 创建映射类对象
                                    if (meta->_hasCustomClassFromDictionary) { // 是否有自定义映射规则
                                        cls = [cls modelCustomClassForDictionary:oneValue];
                                        if (!cls) cls = meta->_genericCls;
                                    }
                                    // new一个_genericCls对象
                                    NSObject *newOne = [cls new];
                                    // 通过yy_modelSetWithDictionary转化为model
                                    [newOne yy_modelSetWithDictionary:(id)oneValue];
                                    if (newOne) dic[oneKey] = newOne;
                                }
                            }];
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, dic);
                        } else {
                            if (meta->_nsType == YYEncodingTypeNSDictionary) {
                                ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, value);
                            } else {
                                ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model,
                                                                               meta->_setter,
                                                                               ((NSDictionary *)value).mutableCopy);
                            }
                        }
                    }
                } break;
                    
                case YYEncodingTypeNSSet:
                case YYEncodingTypeNSMutableSet: { // NSSet类型
                    NSSet *valueSet = nil;
                    if ([value isKindOfClass:[NSArray class]]) valueSet = [NSMutableSet setWithArray:value];
                    else if ([value isKindOfClass:[NSSet class]]) valueSet = ((NSSet *)value);
                    
                    if (meta->_genericCls) {
                        NSMutableSet *set = [NSMutableSet new];
                        for (id one in valueSet) {
                            if ([one isKindOfClass:meta->_genericCls]) {
                                [set addObject:one];
                            } else if ([one isKindOfClass:[NSDictionary class]]) {
                                Class cls = meta->_genericCls;
                                if (meta->_hasCustomClassFromDictionary) {
                                    cls = [cls modelCustomClassForDictionary:one];
                                    if (!cls) cls = meta->_genericCls; // for xcode code coverage
                                }
                                NSObject *newOne = [cls new];
                                [newOne yy_modelSetWithDictionary:one];
                                if (newOne) [set addObject:newOne];
                            }
                        }
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, set);
                    } else {
                        if (meta->_nsType == YYEncodingTypeNSSet) {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, valueSet);
                        } else {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model,
                                                                           meta->_setter,
                                                                           ((NSSet *)valueSet).mutableCopy);
                        }
                    }
                } // break; commented for code coverage in next line
                    
                default: break;
            }
        }
    } else { // 其他类型 自定义的类型，Class，Block，C字符串等
        BOOL isNull = (value == (id)kCFNull);
        switch (meta->_type & YYEncodingTypeMask) {
                
                // 自定义类型
            case YYEncodingTypeObject: {
                if (isNull) { // 如果为空 设置nil
                    ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, (id)nil);
                    
                } else if ([value isKindOfClass:meta->_cls] || !meta->_cls) { // 匹配Class
                    ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, (id)value);
                    
                } else if ([value isKindOfClass:[NSDictionary class]]) { // 为NSDictionary类型
                    NSObject *one = nil;
                    if (meta->_getter) {
                        one = ((id (*)(id, SEL))(void *) objc_msgSend)((id)model, meta->_getter);
                    }
                    if (one) { // 通过yy_modelSetWithDictionary进行转换
                        [one yy_modelSetWithDictionary:value];
                    } else {
                        
                        // 取得meta的cls进行转换
                        Class cls = meta->_cls;
                        if (meta->_hasCustomClassFromDictionary) {
                            cls = [cls modelCustomClassForDictionary:value];
                            if (!cls) cls = meta->_genericCls; // for xcode code coverage
                        }
                        // 将one创建为cls类型
                        one = [cls new];
                        [one yy_modelSetWithDictionary:value];
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)model, meta->_setter, (id)one);
                    }
                }
            } break;
                // Class 类型
            case YYEncodingTypeClass: {
                if (isNull) {
                    ((void (*)(id, SEL, Class))(void *) objc_msgSend)((id)model, meta->_setter, (Class)NULL);
                } else {
                    Class cls = nil;
                    if ([value isKindOfClass:[NSString class]]) {
                        // 从value中获取对应的class
                        cls = NSClassFromString(value);
                        if (cls) {
                            ((void (*)(id, SEL, Class))(void *) objc_msgSend)((id)model, meta->_setter, (Class)cls);
                        }
                    } else {
                        cls = object_getClass(value);
                        if (cls) {
                            if (class_isMetaClass(cls)) { // 判断是否为元类
                                ((void (*)(id, SEL, Class))(void *) objc_msgSend)((id)model, meta->_setter, (Class)value);
                            }
                        }
                    }
                }
            } break;
                
                // SEL
            case  YYEncodingTypeSEL: {
                if (isNull) {
                    ((void (*)(id, SEL, SEL))(void *) objc_msgSend)((id)model, meta->_setter, (SEL)NULL);
                } else if ([value isKindOfClass:[NSString class]]) {
                    // 从SEL字符串中创建SEL 只能接受NSString
                    SEL sel = NSSelectorFromString(value);
                    if (sel) ((void (*)(id, SEL, SEL))(void *) objc_msgSend)((id)model, meta->_setter, (SEL)sel);
                }
            } break;
                // block类型
            case YYEncodingTypeBlock: {
                if (isNull) {
                    ((void (*)(id, SEL, void (^)()))(void *) objc_msgSend)((id)model, meta->_setter, (void (^)())NULL);
                } else if ([value isKindOfClass:YYNSBlockClass()]) { // 取得block的类
                    ((void (*)(id, SEL, void (^)()))(void *) objc_msgSend)((id)model, meta->_setter, (void (^)())value);
                }
            } break;
                
                // Struce , Union , CArray
            case YYEncodingTypeStruct:
            case YYEncodingTypeUnion:
            case YYEncodingTypeCArray: {
                // 需要用NSValue来对这些类型包装为对象
                if ([value isKindOfClass:[NSValue class]]) {
                    // 值编码
                    const char *valueType = ((NSValue *)value).objCType;
                    // 属性编码
                    const char *metaType = meta->_info.typeEncoding.UTF8String;
                    // 值编码和属性类型编码必须一致
                    if (valueType && metaType && strcmp(valueType, metaType) == 0) {
                        // KVC进行赋值
                        [model setValue:value forKey:meta->_name];
                    }
                }
            } break;
                
                // 指针类型 和 CString
            case YYEncodingTypePointer:
            case YYEncodingTypeCString: {
                if (isNull) { // 空处理 用setter方法
                    ((void (*)(id, SEL, void *))(void *) objc_msgSend)((id)model, meta->_setter, (void *)NULL);
                } else if ([value isKindOfClass:[NSValue class]]) {
                    NSValue *nsValue = value;
                    // 查了一下编码表 这里用^V值的是 void＊
                    // + (NSValue *)valueWithPointer:(nullable const void *)pointer;
                    // 需要用NSValue来进行封装 所以获取刀的也就是void *
                    if (nsValue.objCType && strcmp(nsValue.objCType, "^v") == 0) {
                        ((void (*)(id, SEL, void *))(void *) objc_msgSend)((id)model, meta->_setter, nsValue.pointerValue);
                    }
                }
            }
            default: break;
        }
    }
}


/**
 *  此举是为了把对象类的描述，对象，和字典封装在一起
 */
typedef struct {
    // 1. ClassMeta指针
    void *modelMeta;
    // 2. Class 对象的指针
    void *model;
    // 3. json 数据
    void *dictionary;
} ModelSetContext;

/**
 提供一个方法来设置对象的属性值 根据jsonkey和value
 */
static void ModelSetWithDictionaryFunction(const void *_key, const void *_value, void *_context) {
    // 这里获取到ModelSetContext 原来struct中定义的 void*指针 其实就是OC中的id指针
    ModelSetContext *context = _context;
    // 创建Meta类
    __unsafe_unretained _YYModelMeta *meta = (__bridge _YYModelMeta *)(context->modelMeta);
    // 创建PropertyMeta类
    __unsafe_unretained _YYModelPropertyMeta *propertyMeta = [meta->_mapper objectForKey:(__bridge id)(_key)];
    // 获得对象 将C转化成OC
    __unsafe_unretained id model = (__bridge id)(context->model);
    // 多个不同的属性映射一个jsonKey的时候 循环赋值
    while (propertyMeta) {
        if (propertyMeta->_setter) {
            // 为Model 的property设置value: 这里用到之前写好的ModelSetValueForProperty方法根据propertyMeta用来判断类型做转化操作等对Model的Property进行赋值
            ModelSetValueForProperty(model, (__bridge __unsafe_unretained id)_value, propertyMeta);
        }
        // 这里就是我们之前说到的链表结构的next指针
        propertyMeta = propertyMeta->_next;
    };
}

/**
 传入一个dictionary，根据propertyMeta，获取到对应的value
 */
static void ModelSetWithPropertyMetaArrayFunction(const void *_propertyMeta, void *_context) {
    ModelSetContext *context = _context;
    __unsafe_unretained NSDictionary *dictionary = (__bridge NSDictionary *)(context->dictionary);
    __unsafe_unretained _YYModelPropertyMeta *propertyMeta = (__bridge _YYModelPropertyMeta *)(_propertyMeta);
    if (!propertyMeta->_setter) return;
    id value = nil;
    
    // 三种不同的key映射关系 判断是其中哪一种
    if (propertyMeta->_mappedToKeyArray) {
        value = YYValueForMultiKeys(dictionary, propertyMeta->_mappedToKeyArray);
    } else if (propertyMeta->_mappedToKeyPath) {
        value = YYValueForKeyPath(dictionary, propertyMeta->_mappedToKeyPath);
    } else {
        value = [dictionary objectForKey:propertyMeta->_mappedToKey];
    }
    
    if (value) { // 获取到value 对model进行赋值
        __unsafe_unretained id model = (__bridge id)(context->model);
        ModelSetValueForProperty(model, value, propertyMeta);
    }
}

/**
 将model转化成一个合法的json object对象，NSArray/NSDictionary/NSString/NSNumber/NSNull
 */
static id ModelToJSONObjectRecursive(NSObject *model) {
    // 1. 空处理
    if (!model || model == (id)kCFNull) return model;
    // 2. NSString的话直接返回
    if ([model isKindOfClass:[NSString class]]) return model;
    // 3. Number
    if ([model isKindOfClass:[NSNumber class]]) return model;
    // 4. NSDicitionary
    if ([model isKindOfClass:[NSDictionary class]]) {
        // 用NSJSONSerialization来判断NSDictionary的Model对象是否可以转化成Json Object
        if ([NSJSONSerialization isValidJSONObject:model]) return model;
        // 如果不可以转化成json object 需要我们做一些处理
        NSMutableDictionary *newDic = [NSMutableDictionary new];
        // 遍历key value
        [((NSDictionary *)model) enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            // 对key做处理，如果是NSString就直接取，不然取对象的description返回的NSString做key
            NSString *stringKey = [key isKindOfClass:[NSString class]] ? key : key.description;
            // 判断是否为空
            if (!stringKey) return;
            // 递归value做json object处理
            id jsonObj = ModelToJSONObjectRecursive(obj);
            // 如果转换不成功就设置为null
            if (!jsonObj) jsonObj = (id)kCFNull;
            // 更新到newDic中
            newDic[stringKey] = jsonObj;
        }];
        // 返回处理后的NSDictionary
        return newDic;
    }
    
    // 5. NSSet
    if ([model isKindOfClass:[NSSet class]]) {
        // 先将set中所有的value转为数组，在用NSJSONSerialization判断是否为Json Objcet
        NSArray *array = ((NSSet *)model).allObjects;
        if ([NSJSONSerialization isValidJSONObject:array]) return array;
        // NSArray需要做以下的处理
        NSMutableArray *newArray = [NSMutableArray new];
        for (id obj in array) {
            //NSString 和 NSNumber 不需要处理
            if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) {
                [newArray addObject:obj];
            } else { // 如果为其他的类型，递归进行处理
                id jsonObj = ModelToJSONObjectRecursive(obj);
                // 空处理
                if (jsonObj && jsonObj != (id)kCFNull) [newArray addObject:jsonObj];
            }
        }
        return newArray;
    }
    
    // 6. NSArray
    if ([model isKindOfClass:[NSArray class]]) {
        // 用NSJSONSerialization判断是否为Json Objcet
        if ([NSJSONSerialization isValidJSONObject:model]) return model;
        NSMutableArray *newArray = [NSMutableArray new];
        // 对NSArray中的元素做处理
        for (id obj in (NSArray *)model) {
            if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) {
                [newArray addObject:obj];
            } else { // 如果为其他的类型，递归进行处理
                id jsonObj = ModelToJSONObjectRecursive(obj);
                if (jsonObj && jsonObj != (id)kCFNull) [newArray addObject:jsonObj];
            }
        }
        return newArray;
    }
    
    // NSURL NSDate NSURL 都处理为NSString
    if ([model isKindOfClass:[NSURL class]]) return ((NSURL *)model).absoluteString;
    if ([model isKindOfClass:[NSAttributedString class]]) return ((NSAttributedString *)model).string;
    if ([model isKindOfClass:[NSDate class]]) return [YYISODateFormatter() stringFromDate:(id)model];
    // NSData不支持转为JSON
    if ([model isKindOfClass:[NSData class]]) return nil;
    
    // 7. 自定义对象
    // 用modelMeta来描述Model
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:[model class]];
    // 对映射值和meta进行判断处理
    if (!modelMeta || modelMeta->_keyMappedCount == 0) return nil;
    // 创建一个字典 用来转载自定义model的property和value
    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:64];
    // 防止在block中被retain和release
    __unsafe_unretained NSMutableDictionary *dic = result;
    // 遍历_mapper字典中保存的key property 映射关系表
    [modelMeta->_mapper enumerateKeysAndObjectsUsingBlock:^(NSString *propertyMappedKey, _YYModelPropertyMeta *propertyMeta, BOOL *stop) {
        // 没有实现getter的话就直接返回 我们知道YYModel这边主要是通过setter 和 getter方法来取值和赋值的
        if (!propertyMeta->_getter) return;
        
        id value = nil;
        // 如果是基础数据类型 就用ModelCreateNumberFromProperty转化为NSNumber NSDictionary只能存储对象
        if (propertyMeta->_isCNumber) {
            value = ModelCreateNumberFromProperty(model, propertyMeta);
            
        } else if (propertyMeta->_nsType) { // 如果是NSFoundation类型 就需要再次递归解析
            // 通过getter方法来取得对应的值进行解析
            id v = ((id (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyMeta->_getter);
            value = ModelToJSONObjectRecursive(v);
        } else { // 其他类型
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject: { // 自定义类型
                    // 获取对应的值
                    id v = ((id (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyMeta->_getter);
                    // 进行递归解析NSObject自定义类
                    value = ModelToJSONObjectRecursive(v);
                    // 空处理
                    if (value == (id)kCFNull) value = nil;
                } break;
                    
                case YYEncodingTypeClass: { // Class 类型
                    Class v = ((Class (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyMeta->_getter);
                    // 把Class转化为NSString
                    value = v ? NSStringFromClass(v) : nil;
                } break;
                case YYEncodingTypeSEL: { // SEL
                    // SEL转化为NSString
                    SEL v = ((SEL (*)(id, SEL))(void *) objc_msgSend)((id)model, propertyMeta->_getter);
                    value = v ? NSStringFromSelector(v) : nil;
                } break;
                default: break;
            }
        }
        
        // 对象转换失败，直接返回空
        if (!value) return;
        
        // 将转化后的value存到字典中 mappedKey : value
        if (propertyMeta->_mappedToKeyPath) {
            NSMutableDictionary *superDic = dic;
            NSMutableDictionary *subDic = nil;
            // 可能需要多层处理，如果是KeyPath需要嵌套NSDictionary
            /*
             @{
                @"order" : @{
                                @"orderID" : @"312312312313";
                                @"orderNum" : @1;
                                ...
                            }
             }
             */
            for (NSUInteger i = 0, max = propertyMeta->_mappedToKeyPath.count; i < max; i++) {
                // 取出每一个key
                NSString *key = propertyMeta->_mappedToKeyPath[i];
                if (i + 1 == max) { // 判断是否为最后一个
                    if (!superDic[key]) superDic[key] = value;
                    break;
                }
                
                // 通过外层的NSDicitionary获取到内层的字典
                subDic = superDic[key];
                if (subDic) { // 如果存在
                    if ([subDic isKindOfClass:[NSDictionary class]]) {
                        subDic = subDic.mutableCopy;
                        superDic[key] = subDic;
                    } else {
                        break;
                    }
                } else { // 不存在就新建
                    subDic = [NSMutableDictionary new];
                    superDic[key] = subDic;
                }
                // 内层字典作为新的外层字典
                superDic = subDic;
                subDic = nil;
            }
        } else {
            if (!dic[propertyMeta->_mappedToKey]) {
                dic[propertyMeta->_mappedToKey] = value;
            }
        }
    }];
    
    if (modelMeta->_hasCustomTransformToDictionary) {
        // 查看是否转换正确
        BOOL suc = [((id<YYModel>)model) modelCustomTransformToDictionary:dic];
        if (!suc) return nil;
    }
    // 返回对应的Json Object
    return result;
}

/// 添加缩进字符
static NSMutableString *ModelDescriptionAddIndent(NSMutableString *desc, NSUInteger indent) {
    for (NSUInteger i = 0, max = desc.length; i < max; i++) {
        unichar c = [desc characterAtIndex:i];
        if (c == '\n') {
            // 为下一行行首添加缩进
            for (NSUInteger j = 0; j < indent; j++) {
                [desc insertString:@"    " atIndex:i + 1];
            }
            i += indent * 4;
            max += indent * 4;
        }
    }
    return desc;
}

/// 生成一个描述Model的字符串
static NSString *ModelDescription(NSObject *model) {
    // 最大描述长度
    static const int kDescMaxLength = 100;
    // 空处理
    if (!model) return @"<nil>";
    if (model == (id)kCFNull) return @"<null>";
    
    // 如果不是NSObject的子类
    if (![model isKindOfClass:[NSObject class]]) return [NSString stringWithFormat:@"%@",model];
    
    // 取得类描述ModelMeta
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:model.class];
    switch (modelMeta->_nsType) { // 判断是否为NSFoundation
            // String 类型直接返回
        case YYEncodingTypeNSString: case YYEncodingTypeNSMutableString: {
            return [NSString stringWithFormat:@"\"%@\"",model];
        }
        
        case YYEncodingTypeNSValue:
        case YYEncodingTypeNSData: case YYEncodingTypeNSMutableData: {
            // 取得model的description
            NSString *tmp = model.description;
            if (tmp.length > kDescMaxLength) { // 判断长于限定长度 如果是就做省略处理
                tmp = [tmp substringToIndex:kDescMaxLength];
                tmp = [tmp stringByAppendingString:@"..."];
            }
            return tmp;
        }
            
        case YYEncodingTypeNSNumber:
        case YYEncodingTypeNSDecimalNumber:
        case YYEncodingTypeNSDate:
        case YYEncodingTypeNSURL: { // 直接显示Model
            return [NSString stringWithFormat:@"%@",model];
        }
            
            // NSSet先转为NSArray 这里没有做break 为了与NSArray一起做处理
        case YYEncodingTypeNSSet:
        case YYEncodingTypeNSMutableSet: {
            model = ((NSSet *)model).allObjects;
        } // no break
            
            // NSArray 处理
        case YYEncodingTypeNSArray:
        case YYEncodingTypeNSMutableArray: {
            NSArray *array = (id)model;
            NSMutableString *desc = [NSMutableString new];
            if (array.count == 0) { // 判断是否为空
                return [desc stringByAppendingString:@"[]"];
            } else {
                /* 拼接成
                 [
                    "aaaa";
                    "bbbb";
                 ]
                 
                 */
                [desc appendFormat:@"[\n"];
                for (NSUInteger i = 0, max = array.count; i < max; i++) {
                    NSObject *obj = array[i];
                    [desc appendString:@"    "];
                    [desc appendString:ModelDescriptionAddIndent(ModelDescription(obj).mutableCopy, 1)];
                    [desc appendString:(i + 1 == max) ? @"\n" : @";\n"];
                }
                [desc appendString:@"]"];
                return desc;
            }
        }
            
            // 字典处理
        case YYEncodingTypeNSDictionary: case YYEncodingTypeNSMutableDictionary: {
            NSDictionary *dic = (id)model;
            NSMutableString *desc = [NSMutableString new];
            if (dic.count == 0) { // 空处理
                return [desc stringByAppendingString:@"{}"];
            } else {
                /* 
                 {
                    key1 = value1;
                    key2 = value2;
                 }
                 */
                NSArray *keys = dic.allKeys;
                
                [desc appendFormat:@"{\n"];
                for (NSUInteger i = 0, max = keys.count; i < max; i++) {
                    NSString *key = keys[i];
                    NSObject *value = dic[key];
                    [desc appendString:@"    "];
                    [desc appendFormat:@"%@ = %@",key, ModelDescriptionAddIndent(ModelDescription(value).mutableCopy, 1)];
                    [desc appendString:(i + 1 == max) ? @"\n" : @";\n"];
                }
                [desc appendString:@"}"];
            }
            return desc;
        }
        
        default: { // 自定义类
            NSMutableString *desc = [NSMutableString new];
            // <类名：内存地址>
            [desc appendFormat:@"<%@: %p>", model.class, model];
            if (modelMeta->_allPropertyMetas.count == 0) return desc;
            
            // 取得Property的名字 进行排序
            NSArray *properties = [modelMeta->_allPropertyMetas
                                   sortedArrayUsingComparator:^NSComparisonResult(_YYModelPropertyMeta *p1, _YYModelPropertyMeta *p2) {
                                       return [p1->_name compare:p2->_name];
                                   }];
            
            [desc appendFormat:@" {\n"];
            for (NSUInteger i = 0, max = properties.count; i < max; i++) {
                _YYModelPropertyMeta *property = properties[i];
                NSString *propertyDesc;
                if (property->_isCNumber) { // C基础数据类型，先转为NSNumber 再通过NSNumber转为String
                    NSNumber *num = ModelCreateNumberFromProperty(model, property);
                    propertyDesc = num.stringValue;
                } else { // 判断类型
                    switch (property->_type & YYEncodingTypeMask) {
                        case YYEncodingTypeObject: { // 自定义对象或者是NSFoundation
                            id v = ((id (*)(id, SEL))(void *) objc_msgSend)((id)model, property->_getter);
                            // 递归处理
                            propertyDesc = ModelDescription(v);
                            if (!propertyDesc) propertyDesc = @"<nil>";
                        } break;
                        case YYEncodingTypeClass: { // Class类型
                            id v = ((id (*)(id, SEL))(void *) objc_msgSend)((id)model, property->_getter);
                            propertyDesc = ((NSObject *)v).description;
                            if (!propertyDesc) propertyDesc = @"<nil>";
                        } break;
                        case YYEncodingTypeSEL: {
                            // SEL
                            SEL sel = ((SEL (*)(id, SEL))(void *) objc_msgSend)((id)model, property->_getter);
                            if (sel) propertyDesc = NSStringFromSelector(sel);
                            else propertyDesc = @"<NULL>";
                        } break;
                        case YYEncodingTypeBlock: {
                            // Block 类型
                            id block = ((id (*)(id, SEL))(void *) objc_msgSend)((id)model, property->_getter);
                            propertyDesc = block ? ((NSObject *)block).description : @"<nil>";
                        } break;
                            // CArray CString Pointer
                        case YYEncodingTypeCArray: case YYEncodingTypeCString: case YYEncodingTypePointer: {
                            void *pointer = ((void* (*)(id, SEL))(void *) objc_msgSend)((id)model, property->_getter);
                            propertyDesc = [NSString stringWithFormat:@"%p",pointer];
                        } break;
                        case YYEncodingTypeStruct: case YYEncodingTypeUnion: {
                            // 结构体 包装成NSValue
                            NSValue *value = [model valueForKey:property->_name];
                            propertyDesc = value ? value.description : @"{unknown}";
                        } break;
                        default: propertyDesc = @"<unknown>";
                    }
                }
                
                // 拼接为 key ＝ value的形式
                propertyDesc = ModelDescriptionAddIndent(propertyDesc.mutableCopy, 1);
                [desc appendFormat:@"    %@ = %@",property->_name, propertyDesc];
                [desc appendString:(i + 1 == max) ? @"\n" : @";\n"];
            }
            [desc appendFormat:@"}"];
            return desc;
        }
    }
}


@implementation NSObject (YYModel)
// 提供json转字典
+ (NSDictionary *)_yy_dictionaryWithJSON:(id)json {
    
    // 空处理
    if (!json || json == (id)kCFNull) return nil;
    NSDictionary *dic = nil;
    NSData *jsonData = nil;
    // 判断json的类型
    if ([json isKindOfClass:[NSDictionary class]]) {
        dic = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        // json 专为Data
        jsonData = [(NSString *)json dataUsingEncoding : NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSData class]]) {
        jsonData = json;
    }
    // 通过Data 解析为 NSDictionary
    if (jsonData) {
        dic = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
        if (![dic isKindOfClass:[NSDictionary class]]) dic = nil;
    }
    return dic;
}

// json 转 Model
+ (instancetype)yy_modelWithJSON:(id)json {
    // 1. 先把数据转为NSDictionary
    NSDictionary *dic = [self _yy_dictionaryWithJSON:json];
    // 2. 调用json Dict 转 model
    return [self yy_modelWithDictionary:dic];
}

// dicitonay 转 model
+ (instancetype)yy_modelWithDictionary:(NSDictionary *)dictionary {
    // 空处理
    if (!dictionary || dictionary == (id)kCFNull) return nil;
    // 不是NSDictionary对象
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    
    // 取得类对象
    Class cls = [self class];
    
    // 创建类对象的描述信息
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:cls];
    // 是否有；实现自己的映射字典
    if (modelMeta->_hasCustomClassFromDictionary) {
        cls = [cls modelCustomClassForDictionary:dictionary] ?: cls;
    }
    
    // 创建对象
    NSObject *one = [cls new];
    
    // 在这里再一步验证是否能从model转回为Dictionary
    if ([one yy_modelSetWithDictionary:dictionary]) return one;
    return nil;
}

// 从传入的json数据来判断是否能转为Model
- (BOOL)yy_modelSetWithJSON:(id)json {
    // 先转为NSDictionary
    NSDictionary *dic = [NSObject _yy_dictionaryWithJSON:json];
    // 调用字典的验证方法yy_modelSetWithDictionary
    return [self yy_modelSetWithDictionary:dic];
}

// 判断传入的字典是否可以转为Model
- (BOOL)yy_modelSetWithDictionary:(NSDictionary *)dic {
    // 空处理
    if (!dic || dic == (id)kCFNull) return NO;
    // json不是对象
    if (![dic isKindOfClass:[NSDictionary class]]) return NO;
    

    // 创建Model的描述类meta
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:object_getClass(self)];
    // 如果model需要映射的值为0 则直接返回no
    if (modelMeta->_keyMappedCount == 0) return NO;
    
    // 是否实现了自己的映射表
    if (modelMeta->_hasCustomWillTransformFromDictionary) {
        dic = [((id<YYModel>)self) modelCustomWillTransformFromDictionary:dic];
        if (![dic isKindOfClass:[NSDictionary class]]) return NO;
    }
    
    // 创建对象类的描述，对象，和字典的结构体
    ModelSetContext context = {0};
    context.modelMeta = (__bridge void *)(modelMeta);
    context.model = (__bridge void *)(self);
    context.dictionary = (__bridge void *)(dic);
    
    // 字典值和对象对应的属性相互匹配
    // 判断property和json的count的大小，以小的那个为标准
    if (modelMeta->_keyMappedCount >= CFDictionaryGetCount((CFDictionaryRef)dic)) {
        // 对属性名和对应的json key 做赋值处理
        CFDictionaryApplyFunction((CFDictionaryRef)dic, ModelSetWithDictionaryFunction, &context);
        if (modelMeta->_keyPathPropertyMetas) {
            CFArrayApplyFunction((CFArrayRef)modelMeta->_keyPathPropertyMetas,
                                 CFRangeMake(0, CFArrayGetCount((CFArrayRef)modelMeta->_keyPathPropertyMetas)),
                                 ModelSetWithPropertyMetaArrayFunction,
                                 &context);
        }
        if (modelMeta->_multiKeysPropertyMetas) {
            CFArrayApplyFunction((CFArrayRef)modelMeta->_multiKeysPropertyMetas,
                                 CFRangeMake(0, CFArrayGetCount((CFArrayRef)modelMeta->_multiKeysPropertyMetas)),
                                 ModelSetWithPropertyMetaArrayFunction,
                                 &context);
        }
    } else { // 以property的count做标准
        CFArrayApplyFunction((CFArrayRef)modelMeta->_allPropertyMetas,
                             CFRangeMake(0, modelMeta->_keyMappedCount),
                             ModelSetWithPropertyMetaArrayFunction,
                             &context);
    }
    
    // 有实现自定义的映射关系表
    if (modelMeta->_hasCustomTransformFromDictionary) {
        return [((id<YYModel>)self) modelCustomTransformFromDictionary:dic];
    }
    return YES;
}

- (id)yy_modelToJSONObject {

    // 转化成可以json化的对象
    id jsonObject = ModelToJSONObjectRecursive(self);
    // 只有NSArray 和 NSDictionary才能转化成jsonObject
    if ([jsonObject isKindOfClass:[NSArray class]]) return jsonObject;
    if ([jsonObject isKindOfClass:[NSDictionary class]]) return jsonObject;
    return nil;
}


// 将model转为 json data
- (NSData *)yy_modelToJSONData {
    // 先转为可以序列化的Json Object
    id jsonObject = [self yy_modelToJSONObject];
    if (!jsonObject) return nil;
    // 解析为NSData
    return [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:NULL];
}

// 将model转为对应的NSString类
- (NSString *)yy_modelToJSONString {
    NSData *jsonData = [self yy_modelToJSONData];
    if (jsonData.length == 0) return nil;
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

// 对对象进行拷贝 ： 浅拷贝
- (id)yy_modelCopy{
    // 空处理
    if (self == (id)kCFNull) return self;
    
    // 创建meta类
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    if (modelMeta->_nsType) return [self copy];
    
    // 创建一个实例
    NSObject *one = [self.class new];
    
    // 遍历propertyMeta
    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        // 判断是否有getter方法和setter方法
        if (!propertyMeta->_getter || !propertyMeta->_setter) continue;
            // 如果是C数据类型
        if (propertyMeta->_isCNumber) {
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeBool: {
                    bool num = ((bool (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, bool))(void *) objc_msgSend)((id)one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeInt8:
                case YYEncodingTypeUInt8: {
                    uint8_t num = ((bool (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, uint8_t))(void *) objc_msgSend)((id)one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeInt16:
                case YYEncodingTypeUInt16: {
                    uint16_t num = ((uint16_t (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, uint16_t))(void *) objc_msgSend)((id)one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeInt32:
                case YYEncodingTypeUInt32: {
                    uint32_t num = ((uint32_t (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, uint32_t))(void *) objc_msgSend)((id)one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeInt64:
                case YYEncodingTypeUInt64: {
                    uint64_t num = ((uint64_t (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, uint64_t))(void *) objc_msgSend)((id)one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeFloat: {
                    float num = ((float (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, float))(void *) objc_msgSend)((id)one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeDouble: {
                    double num = ((double (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, double))(void *) objc_msgSend)((id)one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeLongDouble: {
                    long double num = ((long double (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, long double))(void *) objc_msgSend)((id)one, propertyMeta->_setter, num);
                } // break; commented for code coverage in next line
                default: break;
            }
        } else {
             // 其他类型
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject:
                case YYEncodingTypeClass:
                case YYEncodingTypeBlock: {
                    id value = ((id (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)one, propertyMeta->_setter, value);
                } break;
                case YYEncodingTypeSEL:
                case YYEncodingTypePointer:
                case YYEncodingTypeCString: {
                    size_t value = ((size_t (*)(id, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_getter);
                    ((void (*)(id, SEL, size_t))(void *) objc_msgSend)((id)one, propertyMeta->_setter, value);
                } break;
                case YYEncodingTypeStruct:
                case YYEncodingTypeUnion: {
                    @try {
                        NSValue *value = [self valueForKey:NSStringFromSelector(propertyMeta->_getter)];
                        if (value) {
                            [one setValue:value forKey:propertyMeta->_name];
                        }
                    } @catch (NSException *exception) {}
                } // break; commented for code coverage in next line
                default: break;
            }
        }
    }
    return one;
}

// 对对象的属性进行归档
- (void)yy_modelEncodeWithCoder:(NSCoder *)aCoder {
    if (!aCoder) return;
    if (self == (id)kCFNull) {
        [((id<NSCoding>)self)encodeWithCoder:aCoder];
        return;
    }
    
    // 获取描述类
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    if (modelMeta->_nsType) {
        // 如果是NSFoundation的类 直接归档
        [((id<NSCoding>)self)encodeWithCoder:aCoder];
        return;
    }
    
    // 遍历每一个propertyMeta 进行归档
    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        // 判断是否有实现getter方法
        if (!propertyMeta->_getter) return;
        
        // C类型 包装为NSNumber进行归档
        if (propertyMeta->_isCNumber) {
            NSNumber *value = ModelCreateNumberFromProperty(self, propertyMeta);
            if (value) [aCoder encodeObject:value forKey:propertyMeta->_name];
        } else {
    
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject: { // 如果是自定义对象
                    id value = ((id (*)(id, SEL))(void *)objc_msgSend)((id)self, propertyMeta->_getter);
                    if (value && (propertyMeta->_nsType || [value respondsToSelector:@selector(encodeWithCoder:)])) {
                        // 用 encodeObject 进行归档 对NSValue做特殊处理 只归档NSNumber类型
                        if ([value isKindOfClass:[NSValue class]]) {
                            if ([value isKindOfClass:[NSNumber class]]) {
                                [aCoder encodeObject:value forKey:propertyMeta->_name];
                            }
                        } else {
                            [aCoder encodeObject:value forKey:propertyMeta->_name];
                        }
                    }
                } break;
                case YYEncodingTypeSEL: { // 包装成NSString进行归档
                    SEL value = ((SEL (*)(id, SEL))(void *)objc_msgSend)((id)self, propertyMeta->_getter);
                    if (value) {
                        NSString *str = NSStringFromSelector(value);
                        [aCoder encodeObject:str forKey:propertyMeta->_name];
                    }
                } break;
                case YYEncodingTypeStruct:
                case YYEncodingTypeUnion: {
                    if (propertyMeta->_isKVCCompatible && propertyMeta->_isStructAvailableForKeyedArchiver) {
                        @try {
                            NSValue *value = [self valueForKey:NSStringFromSelector(propertyMeta->_getter)];
                            [aCoder encodeObject:value forKey:propertyMeta->_name];
                        } @catch (NSException *exception) {}
                    }
                } break;
                    
                default:
                    break;
            }
        }
    }
}

// 对象解档
- (id)yy_modelInitWithCoder:(NSCoder *)aDecoder {
    // 空处理
    if (!aDecoder) return self;
    if (self == (id)kCFNull) return self;    
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    if (modelMeta->_nsType) return self;
    
    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        // 通过setter方法来赋值
        if (!propertyMeta->_setter) continue;
        
        if (propertyMeta->_isCNumber) {
            // 取出NSNumber 转化为对应的类型
            NSNumber *value = [aDecoder decodeObjectForKey:propertyMeta->_name];
            if ([value isKindOfClass:[NSNumber class]]) {
                ModelSetNumberToProperty(self, value, propertyMeta);
                // ？？？这里一直不能理解需要对value做这个处理
                [value class];
            }
        } else {
            YYEncodingType type = propertyMeta->_type & YYEncodingTypeMask;
            switch (type) {
                case YYEncodingTypeObject: { // 对象直接取出值做处理
                    id value = [aDecoder decodeObjectForKey:propertyMeta->_name];
                    ((void (*)(id, SEL, id))(void *) objc_msgSend)((id)self, propertyMeta->_setter, value);
                } break;
                case YYEncodingTypeSEL: { // 从NSString中取得SEL
                    NSString *str = [aDecoder decodeObjectForKey:propertyMeta->_name];
                    if ([str isKindOfClass:[NSString class]]) {
                        SEL sel = NSSelectorFromString(str);
                        ((void (*)(id, SEL, SEL))(void *) objc_msgSend)((id)self, propertyMeta->_setter, sel);
                    }
                } break;
                case YYEncodingTypeStruct:
                case YYEncodingTypeUnion: {
                    if (propertyMeta->_isKVCCompatible) {
                        @try {
                            NSValue *value = [aDecoder decodeObjectForKey:propertyMeta->_name];
                            if (value) [self setValue:value forKey:propertyMeta->_name];
                        } @catch (NSException *exception) {}
                    }
                } break;
                    
                default:
                    break;
            }
        }
    }
    return self;
}

- (NSUInteger)yy_modelHash {
    if (self == (id)kCFNull) return [self hash];
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    // NSFoundation 的话 直接进行hash
    if (modelMeta->_nsType) return [self hash];
    
    NSUInteger value = 0;
    NSUInteger count = 0;

    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        // 属性必须支持KVC
        if (!propertyMeta->_isKVCCompatible) continue;
        // 取得get方法SEL 进行位运算
        value ^= [[self valueForKey:NSStringFromSelector(propertyMeta->_getter)] hash];
        count++;
    }
    
    // 如果count为空 就输出自身内存地址
    if (count == 0) value = (long)((__bridge void *)self);
    return value;
}

// 实例间的比较
- (BOOL)yy_modelIsEqual:(id)model {
    // 判断地址事否相同
    if (self == model) return YES;
    
    // 类不相同直接return NO
    if (![model isMemberOfClass:self.class]) return NO;
    
    // 包装Model
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    // 判断NSFoundation
    if (modelMeta->_nsType) return [self isEqual:model];
    
    // 判断hash
    if ([self hash] != [model hash]) return NO;
    
    // 对model内的对象进行比较
    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        if (!propertyMeta->_isKVCCompatible) continue;
        // KVC取值
        id this = [self valueForKey:NSStringFromSelector(propertyMeta->_getter)];
        id that = [model valueForKey:NSStringFromSelector(propertyMeta->_getter)];
        if (this == that) continue;
        if (this == nil || that == nil) return NO;
        if (![this isEqual:that]) return NO;
    }
    return YES;
}

- (NSString *)yy_modelDescription {
    return ModelDescription(self);
}

@end



@implementation NSArray (YYModel)

+ (NSArray *)yy_modelArrayWithClass:(Class)cls json:(id)json {
    if (!json) return nil;
    NSArray *arr = nil;
    NSData *jsonData = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        arr = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        jsonData = [(NSString *)json dataUsingEncoding : NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSData class]]) {
        jsonData = json;
    }
    if (jsonData) {
        arr = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
        if (![arr isKindOfClass:[NSArray class]]) arr = nil;
    }
    return [self yy_modelArrayWithClass:cls array:arr];
}

+ (NSArray *)yy_modelArrayWithClass:(Class)cls array:(NSArray *)arr {
    if (!cls || !arr) return nil;
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *dic in arr) {
        if (![dic isKindOfClass:[NSDictionary class]]) continue;
        NSObject *obj = [cls yy_modelWithDictionary:dic];
        if (obj) [result addObject:obj];
    }
    return result;
}

@end


@implementation NSDictionary (YYModel)

+ (NSDictionary *)yy_modelDictionaryWithClass:(Class)cls json:(id)json {
    if (!json) return nil;
    NSDictionary *dic = nil;
    NSData *jsonData = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        dic = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        jsonData = [(NSString *)json dataUsingEncoding : NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSData class]]) {
        jsonData = json;
    }
    if (jsonData) {
        dic = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
        if (![dic isKindOfClass:[NSDictionary class]]) dic = nil;
    }
    return [self yy_modelDictionaryWithClass:cls dictionary:dic];
}

+ (NSDictionary *)yy_modelDictionaryWithClass:(Class)cls dictionary:(NSDictionary *)dic {
    if (!cls || !dic) return nil;
    NSMutableDictionary *result = [NSMutableDictionary new];
    for (NSString *key in dic.allKeys) {
        if (![key isKindOfClass:[NSString class]]) continue;
        NSObject *obj = [cls yy_modelWithDictionary:dic[key]];
        if (obj) result[key] = obj;
    }
    return result;
}

@end
