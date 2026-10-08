#import "ObjCExceptionCatching.h"

NSException *_Nullable BCCatchObjCException(NS_NOESCAPE void (^block)(void)) {
	@try {
		block();
		return nil;
	}
	@catch (NSException *exception) {
		return exception;
	}
}
