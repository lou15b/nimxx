LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := main

SDL_PATH := ../SDL

LOCAL_C_INCLUDES := $(LOCAL_PATH)/$(SDL_PATH)/include $(NIM_INCLUDE_DIR)

ABI_SRC_PATH := $(LOCAL_PATH)/$(APP_ABI)

# Add your application source files here...
LOCAL_SRC_FILES := $(SDL_PATH)/src/main/android/SDL_android_main.c \
	$(patsubst $(ABI_SRC_PATH)/%, $(APP_ABI)/%, $(wildcard $(ABI_SRC_PATH)/*.cpp)) \
	$(patsubst $(ABI_SRC_PATH)/%, $(APP_ABI)/%, $(wildcard $(ABI_SRC_PATH)/*.c))

LOCAL_STATIC_LIBRARIES := $(STATIC_LIBRARIES) SDL2_static
LOCAL_WHOLE_STATIC_LIBRARIES := main_static

LOCAL_LDLIBS := -lGLESv1_CM -lGLESv2 -llog -landroid -lOpenSLES -lc $(ADDITIONAL_LINKER_FLAGS)
LOCAL_CFLAGS := $(ADDITIONAL_COMPILER_FLAGS) -latomic -lc

include $(BUILD_SHARED_LIBRARY)
