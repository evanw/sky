#import <skew.h>
#import "compiled.cpp"
#import <skew.cpp>
#import <sys/time.h>
#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>

@class OpenGLView;

namespace OSX {
  struct Window : Editor::Window {
    void prepareOpenGL() {
    }

    void handleFrame() {
    }

    void handleResize() {
    }

    void setIsActive(bool value) {
    }

    virtual Editor::SemanticRenderer *renderer() override {
      #warning TODO
      return nullptr;
    }

    virtual void setView(Editor::View *view) override {
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
      }
    #endif

  private:
    OpenGLView *nsView = nullptr;
  };

  struct Platform : Editor::Platform {
    virtual Editor::OperatingSystem operatingSystem() override {
      return Editor::OperatingSystem::OSX;
    }

    virtual Editor::UserAgent userAgent() override {
      return Editor::UserAgent::UNKNOWN;
    }

    virtual double nowInSeconds() override {
      timeval data;
      gettimeofday(&data, nullptr);
      return data.tv_sec + data.tv_usec / 1.0e6;
    }

    virtual Graphics::GlyphProvider *createGlyphProvider() override {
      #warning TODO
      return nullptr;
    }

    virtual Editor::Window *createWindow() override {
      #warning TODO
      return new Window;
    }

    #ifdef SKEW_GC_MARK_AND_SWEEP
      virtual void __gc_mark() override {
      }
    #endif
  };
}

@interface AppDelegate : NSObject <NSApplicationDelegate> {
  Skew::Root<Editor::App> _app;
}

@end

@interface OpenGLView : NSOpenGLView <NSWindowDelegate> {
  CVDisplayLinkRef displayLink;
  Skew::Root<OSX::Window> _win;
}

- (id)initWithFrame:(NSRect)frame window:(OSX::Window *)window;

@end

////////////////////////////////////////////////////////////////////////////////

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now, const CVTimeStamp *outputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *context) {
  [(__bridge OpenGLView *)context performSelectorOnMainThread:@selector(invalidate) withObject:nil waitUntilDone:NO];
  return kCVReturnSuccess;
}

@implementation OpenGLView

- (id)initWithFrame:(NSRect)frame window:(OSX::Window *)window {
  NSOpenGLPixelFormatAttribute attributes[] = { NSOpenGLPFADoubleBuffer, 0 };
  auto format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
  self = [super initWithFrame:frame pixelFormat:format];
  [self setWantsBestResolutionOpenGLSurface:YES];
  _win = window;
  return self;
}

- (void)dealloc {
  CVDisplayLinkRelease(displayLink);
}

- (void)prepareOpenGL {
  int swap = 1;
  [[self openGLContext] makeCurrentContext];
  [[self openGLContext] setValues:&swap forParameter:NSOpenGLCPSwapInterval];
  CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
  CVDisplayLinkSetOutputCallback(displayLink, &displayLinkCallback, (__bridge void *)self);
  CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink,
    (CGLContextObj)[[self openGLContext] CGLContextObj],
    (CGLPixelFormatObj)[[self pixelFormat] CGLPixelFormatObj]);
  CVDisplayLinkStart(displayLink);
  _win->prepareOpenGL();
}

- (void)invalidate {
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect {
  _win->handleFrame();
}

- (BOOL)windowShouldClose:(id)sender {
  exit(0);
}

- (void)windowDidResize:(NSNotification *)notification {
  _win->handleResize();
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
  _win->handleResize();
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  _win->setIsActive(true);
}

- (void)windowDidResignKey:(NSNotification *)notification {
  _win->setIsActive(false);
}

@end

////////////////////////////////////////////////////////////////////////////////

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(id)sender {
  auto submenu = [[NSMenu alloc] init];
  auto menu = [[NSMenu alloc] init];
  [[menu addItemWithTitle:@"" action:nil keyEquivalent:@""] setSubmenu:submenu];
  [submenu addItemWithTitle:@"Close" action:@selector(windowShouldClose:) keyEquivalent:@"w"];
  // [submenu addItemWithTitle:@"Quit" action:@selector(windowShouldClose:) keyEquivalent:@"q"];
  [[NSApplication sharedApplication] setMainMenu:menu];
  _app = new Editor::App(new OSX::Platform());
}

@end

////////////////////////////////////////////////////////////////////////////////

int main() {
  @autoreleasepool {
    auto application = [NSApplication sharedApplication];
    auto delegate = [[AppDelegate alloc] init]; // This must be stored in a local variable because of ARC
    [application setDelegate:delegate];
    [application activateIgnoringOtherApps:YES];
    [application run];
  }
}
