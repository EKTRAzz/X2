# Makefile for SpatialConvolver.dylib
TARGET = SpatialConvolver.dylib
CC = clang
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

CFLAGS = -arch arm64 -arch arm64e -isysroot $(SDK) -miphoneos-version-min=14.0 -O3 -fobjc-arc -Wall
LDFLAGS = -dynamiclib -framework Foundation -framework AudioToolbox -framework Accelerate

SRCS = SpatialConvolver.m fishhook.c
OBJS = $(SRCS:.c=.o)
OBJS := $(OBJS:.m=.o)

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $(TARGET)
	@echo "Built $(TARGET) successfully!"

clean:
	rm -f $(TARGET) *.o
