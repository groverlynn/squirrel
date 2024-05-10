#import <Carbon/Carbon.h>

typedef CF_OPTIONS(int, RimeInputMode) {
  DEFAULT_INPUT_MODE = 1 << 0,
  HANS_INPUT_MODE = 1 << 0,
  HANT_INPUT_MODE = 1 << 1,
  CANT_INPUT_MODE = 1 << 2
};

RimeInputMode GetEnabledInputModes(void);

void RegisterInputSource(void);
void DisableInputSource(void);
void EnableInputSource(void);
void SelectInputSource(void);

