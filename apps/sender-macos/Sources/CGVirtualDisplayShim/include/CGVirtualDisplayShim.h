//
//  CGVirtualDisplayShim.h
//
//  Declaraciones de las clases privadas de CoreGraphics que crean pantallas
//  virtuales reales (macOS las usa internamente para Sidecar/Continuidad).
//
//  Atribución: interfaces derivadas de Stengo/DeskPad (MIT), que a su vez
//  las tomó de KhaosT/CGVirtualDisplay. Solo declaraciones: las clases ya
//  viven en CoreGraphics.framework, este archivo no implementa nada.
//
//  Por qué API privada: Apple no publica API para crear displays (ADR-006
//  actualizado); es el mismo mecanismo que usan BetterDisplay y DeskPad.
//  Si Apple publica API oficial, se sustituye este shim sin tocar el resto.
//

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplayDescriptor;

@interface CGVirtualDisplayMode : NSObject

@property (readonly, nonatomic) CGFloat refreshRate;
@property (readonly, nonatomic) NSUInteger width;
@property (readonly, nonatomic) NSUInteger height;

- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(CGFloat)refreshRate;

@end

@interface CGVirtualDisplaySettings : NSObject

@property (retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;

- (instancetype)init;

@end

@interface CGVirtualDisplay : NSObject

@property (readonly, nonatomic) NSArray *modes;
@property (readonly, nonatomic) unsigned int hiDPI;
@property (readonly, nonatomic) CGDirectDisplayID displayID;
@property (readonly, nonatomic) NSString *name;

- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;

@end

@interface CGVirtualDisplayDescriptor : NSObject

@property (retain, nonatomic) dispatch_queue_t queue;
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (copy, nonatomic, nullable) void (^terminationHandler)(id, CGVirtualDisplay *);

- (instancetype)init;
- (nullable dispatch_queue_t)dispatchQueue;
- (void)setDispatchQueue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
