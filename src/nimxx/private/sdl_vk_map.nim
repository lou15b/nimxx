import ../keyboard
import std / [ tables, hashes ]
import pkg/sdl2

proc hash(s: Scancode): Hash {.inline.} = hash(int(s))

const virtualKeyMapping: Table[Scancode, VirtualKey] = {
  SDL_SCANCODE_UNKNOWN:          VirtualKey.Unknown,
  SDL_SCANCODE_ESCAPE:           VirtualKey.Escape,
  SDL_SCANCODE_1:                VirtualKey.One,
  SDL_SCANCODE_2:                VirtualKey.Two,
  SDL_SCANCODE_3:                VirtualKey.Three,
  SDL_SCANCODE_4:                VirtualKey.Four,
  SDL_SCANCODE_5:                VirtualKey.Five,
  SDL_SCANCODE_6:                VirtualKey.Six,
  SDL_SCANCODE_7:                VirtualKey.Seven,
  SDL_SCANCODE_8:                VirtualKey.Eight,
  SDL_SCANCODE_9:                VirtualKey.Nine,
  SDL_SCANCODE_0:                VirtualKey.Zero,
  SDL_SCANCODE_MINUS:            VirtualKey.Minus,
  SDL_SCANCODE_EQUALS:           VirtualKey.Equals,
  SDL_SCANCODE_BACKSPACE:        VirtualKey.Backspace,
  SDL_SCANCODE_TAB:              VirtualKey.Tab,
  SDL_SCANCODE_Q:                VirtualKey.Q,
  SDL_SCANCODE_W:                VirtualKey.W,
  SDL_SCANCODE_E:                VirtualKey.E,
  SDL_SCANCODE_R:                VirtualKey.R,
  SDL_SCANCODE_T:                VirtualKey.T,
  SDL_SCANCODE_Y:                VirtualKey.Y,
  SDL_SCANCODE_U:                VirtualKey.U,
  SDL_SCANCODE_I:                VirtualKey.I,
  SDL_SCANCODE_O:                VirtualKey.O,
  SDL_SCANCODE_P:                VirtualKey.P,
  SDL_SCANCODE_LEFTBRACKET:      VirtualKey.LeftBracket,
  SDL_SCANCODE_RIGHTBRACKET:     VirtualKey.RightBracket,
  SDL_SCANCODE_RETURN:           VirtualKey.Return,
  SDL_SCANCODE_LCTRL:            VirtualKey.LeftControl,
  SDL_SCANCODE_A:                VirtualKey.A,
  SDL_SCANCODE_S:                VirtualKey.S,
  SDL_SCANCODE_D:                VirtualKey.D,
  SDL_SCANCODE_F:                VirtualKey.F,
  SDL_SCANCODE_G:                VirtualKey.G,
  SDL_SCANCODE_H:                VirtualKey.H,
  SDL_SCANCODE_J:                VirtualKey.J,
  SDL_SCANCODE_K:                VirtualKey.K,
  SDL_SCANCODE_L:                VirtualKey.L,
  SDL_SCANCODE_SEMICOLON:        VirtualKey.Semicolon,
  SDL_SCANCODE_APOSTROPHE:       VirtualKey.Apostrophe,
  SDL_SCANCODE_GRAVE:            VirtualKey.Backtick,
  SDL_SCANCODE_LSHIFT:           VirtualKey.LeftShift,
  SDL_SCANCODE_BACKSLASH:        VirtualKey.BackSlash,
  SDL_SCANCODE_Z:                VirtualKey.Z,
  SDL_SCANCODE_X:                VirtualKey.X,
  SDL_SCANCODE_C:                VirtualKey.C,
  SDL_SCANCODE_V:                VirtualKey.V,
  SDL_SCANCODE_B:                VirtualKey.B,
  SDL_SCANCODE_N:                VirtualKey.N,
  SDL_SCANCODE_M:                VirtualKey.M,
  SDL_SCANCODE_COMMA:            VirtualKey.Comma,
  SDL_SCANCODE_PERIOD:           VirtualKey.Period,
  SDL_SCANCODE_SLASH:            VirtualKey.Slash,
  SDL_SCANCODE_RSHIFT:           VirtualKey.RightShift,
  SDL_SCANCODE_KP_MULTIPLY:      VirtualKey.KeypadMultiply,
  SDL_SCANCODE_LALT:             VirtualKey.LeftAlt,
  SDL_SCANCODE_SPACE:            VirtualKey.Space,
  SDL_SCANCODE_CAPSLOCK:         VirtualKey.CapsLock,
  SDL_SCANCODE_F1:               VirtualKey.F1,
  SDL_SCANCODE_F2:               VirtualKey.F2,
  SDL_SCANCODE_F3:               VirtualKey.F3,
  SDL_SCANCODE_F4:               VirtualKey.F4,
  SDL_SCANCODE_F5:               VirtualKey.F5,
  SDL_SCANCODE_F6:               VirtualKey.F6,
  SDL_SCANCODE_F7:               VirtualKey.F7,
  SDL_SCANCODE_F8:               VirtualKey.F8,
  SDL_SCANCODE_F9:               VirtualKey.F9,
  SDL_SCANCODE_F10:              VirtualKey.F10,
  SDL_SCANCODE_NUMLOCKCLEAR:     VirtualKey.NumLock,
  SDL_SCANCODE_SCROLLLOCK:       VirtualKey.ScrollLock,
  SDL_SCANCODE_KP_7:             VirtualKey.Keypad7,
  SDL_SCANCODE_KP_8:             VirtualKey.Keypad8,
  SDL_SCANCODE_KP_9:             VirtualKey.Keypad9,
  SDL_SCANCODE_KP_MINUS:         VirtualKey.KeypadMinus,
  SDL_SCANCODE_KP_4:             VirtualKey.Keypad4,
  SDL_SCANCODE_KP_5:             VirtualKey.Keypad5,
  SDL_SCANCODE_KP_6:             VirtualKey.Keypad6,
  SDL_SCANCODE_KP_PLUS:          VirtualKey.KeypadPlus,
  SDL_SCANCODE_KP_1:             VirtualKey.Keypad1,
  SDL_SCANCODE_KP_2:             VirtualKey.Keypad2,
  SDL_SCANCODE_KP_3:             VirtualKey.Keypad3,
  SDL_SCANCODE_KP_0:             VirtualKey.Keypad0,
  SDL_SCANCODE_KP_PERIOD:        VirtualKey.KeypadPeriod,
  SDL_SCANCODE_NONUSBACKSLASH:   VirtualKey.NonUSBackSlash,
  SDL_SCANCODE_F11:              VirtualKey.F11,
  SDL_SCANCODE_F12:              VirtualKey.F12,
  #0:                 VirtualKey.International1, # -
  #0:                 VirtualKey.Lang3, # -
  #0:                 VirtualKey.Lang4, # -
  #0:                 VirtualKey.International4, # -
  #0:                 VirtualKey.International2, # -
  #0:                 VirtualKey.International5, # -
  #0:                 VirtualKey.International6, # -
  SDL_SCANCODE_KP_ENTER:         VirtualKey.KeypadEnter,
  SDL_SCANCODE_RCTRL:            VirtualKey.RightControl,
  SDL_SCANCODE_KP_DIVIDE:        VirtualKey.KeypadDivide,
  SDL_SCANCODE_PRINTSCREEN:      VirtualKey.PrintScreen,
  SDL_SCANCODE_RALT:             VirtualKey.RightAlt,
  SDL_SCANCODE_HOME:             VirtualKey.Home,
  SDL_SCANCODE_UP:               VirtualKey.Up,
  SDL_SCANCODE_PAGEUP:           VirtualKey.PageUp,
  SDL_SCANCODE_LEFT:             VirtualKey.Left,
  SDL_SCANCODE_RIGHT:            VirtualKey.Right,
  SDL_SCANCODE_END:              VirtualKey.End,
  SDL_SCANCODE_DOWN:             VirtualKey.Down,
  SDL_SCANCODE_PAGEDOWN:         VirtualKey.PageDown,
  SDL_SCANCODE_INSERT:           VirtualKey.Insert,
  SDL_SCANCODE_DELETE:           VirtualKey.Delete,
  SDL_SCANCODE_MUTE:             VirtualKey.Mute,
  SDL_SCANCODE_VOLUMEDOWN:       VirtualKey.VolumeDown,
  SDL_SCANCODE_VOLUMEUP:         VirtualKey.VolumeUp,
  SDL_SCANCODE_POWER:            VirtualKey.Power,
  SDL_SCANCODE_KP_EQUALS:        VirtualKey.KeypadEquals,
  SDL_SCANCODE_KP_PLUSMINUS:     VirtualKey.KeypadPlusMinus,
  SDL_SCANCODE_PAUSE:            VirtualKey.Pause,
  SDL_SCANCODE_KP_COMMA:         VirtualKey.KeypadComma,
  #0:                 VirtualKey.Lang1, # -
  #0:                 VirtualKey.Lang2, # -
  SDL_SCANCODE_LGUI:             VirtualKey.LeftGUI,
  SDL_SCANCODE_RGUI:             VirtualKey.RightGUI,
  SDL_SCANCODE_STOP:             VirtualKey.Stop,
  SDL_SCANCODE_AGAIN:            VirtualKey.Again,
  SDL_SCANCODE_UNDO:             VirtualKey.Undo,
  SDL_SCANCODE_COPY:             VirtualKey.Copy,
  SDL_SCANCODE_PASTE:            VirtualKey.Paste,
  SDL_SCANCODE_FIND:             VirtualKey.Find,
  SDL_SCANCODE_CUT:              VirtualKey.Cut,
  SDL_SCANCODE_HELP:             VirtualKey.Help,
  SDL_SCANCODE_MENU:             VirtualKey.Menu,
  SDL_SCANCODE_CALCULATOR:       VirtualKey.Calculator,
  SDL_SCANCODE_SLEEP:            VirtualKey.Sleep,
  SDL_SCANCODE_MAIL:             VirtualKey.Mail,
  SDL_SCANCODE_AC_BOOKMARKS:     VirtualKey.AcBookmarks,
  SDL_SCANCODE_COMPUTER:         VirtualKey.Computer,
  SDL_SCANCODE_AC_BACK:          VirtualKey.AcBack,
  SDL_SCANCODE_AC_FORWARD:       VirtualKey.AcForward,
  SDL_SCANCODE_EJECT:            VirtualKey.Eject,
  SDL_SCANCODE_AUDIONEXT:        VirtualKey.AudioNext,
  SDL_SCANCODE_AUDIOPLAY:        VirtualKey.AudioPlay,
  SDL_SCANCODE_AUDIOPREV:        VirtualKey.AudioPrev,
  SDL_SCANCODE_AC_HOME:          VirtualKey.AcHome,
  SDL_SCANCODE_AC_REFRESH:       VirtualKey.AcRefresh,
  SDL_SCANCODE_KP_LEFTPAREN:     VirtualKey.KeypadLeftPar,
  SDL_SCANCODE_KP_RIGHTPAREN:    VirtualKey.KeypadRightPar,
  SDL_SCANCODE_F13:              VirtualKey.F13,
  SDL_SCANCODE_F14:              VirtualKey.F14,
  SDL_SCANCODE_F15:              VirtualKey.F15,
  SDL_SCANCODE_F16:              VirtualKey.F16,
  SDL_SCANCODE_F17:              VirtualKey.F17,
  SDL_SCANCODE_F18:              VirtualKey.F18,
  SDL_SCANCODE_F19:              VirtualKey.F19,
  SDL_SCANCODE_F20:              VirtualKey.F20,
  SDL_SCANCODE_F21:              VirtualKey.F21,
  SDL_SCANCODE_F22:              VirtualKey.F22,
  SDL_SCANCODE_F23:              VirtualKey.F23,
  SDL_SCANCODE_F24:              VirtualKey.F24,
  SDL_SCANCODE_AC_SEARCH:        VirtualKey.AcSearch,
  SDL_SCANCODE_ALTERASE:         VirtualKey.AltErase,
  SDL_SCANCODE_CANCEL:           VirtualKey.Cancel,
  SDL_SCANCODE_BRIGHTNESSDOWN:   VirtualKey.BrightnessDown,
  SDL_SCANCODE_BRIGHTNESSUP:     VirtualKey.BrightnessUp,
  SDL_SCANCODE_DISPLAYSWITCH:    VirtualKey.DisplaySwitch,
  SDL_SCANCODE_KBDILLUMTOGGLE:   VirtualKey.IlluminateToggle,
  SDL_SCANCODE_KBDILLUMDOWN:     VirtualKey.IlluminateDown,
  SDL_SCANCODE_KBDILLUMUP:       VirtualKey.IlluminateUp
}.toTable()

template virtualKeyFromNative*(kc: cint): VirtualKey = virtualKeyMapping.getOrDefault(cast[Scancode](kc))
