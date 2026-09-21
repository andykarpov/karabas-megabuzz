; =============================================================================
; Karabas MegaBuzz Configurator ROM
; main entry point
; =============================================================================

;        DEFINE DEBUG_MODE
;        DEFINE EMU_MODE

        DEVICE ZXSPECTRUM48
;        OUTPUT "megabuzz.rom"

        ORG 0x0000

Start:
        DI
        LD SP, 0xFFFF       ; Init stack

        ; black border
        XOR A : OUT (0xFE), A

        JP RealStart

        INCLUDE "screen.asm"
        INCLUDE "megabuzz.asm"
        INCLUDE "keyboard.asm"

RealStart:
        CALL Screen.Clear
        CALL Screen.ResetAttributes

        LD DE, LoadingText
        LD BC, 0x0504 ; row 5, col 4
        CALL Screen.PrintString

        ; Selected option = 0
        XOR A
        LD (SelectedOption), A  

        ; Read MegaBuzz config byte
        CALL MegaBuzz.WaitFlash

        CALL Screen.Clear
        CALL Screen.ResetAttributes

        XOR A
        CALL MegaBuzz.ReadConfig
        LD (CheckboxState), A
        LD (InitialConfig), A

        CALL DrawStaticInterface

MainLoop:
        CALL KeyDelay       

.WaitKey:
        CALL Keyboard.Scan   
        LD B, A                 

        CP Keyboard.KEY_UP                 
        JR NZ, .NotUp
        LD A, (SelectedOption)
        AND A
        JR Z, .WaitKey

        LD (OldSelectedOption), A        
        DEC A
        LD (SelectedOption), A
        CALL UpdateFocus
        JR MainLoop

.NotUp:
        CP Keyboard.KEY_DOWN                 
        JR NZ, .NotDown
        LD A, (SelectedOption)
        CP 9                    ; 0-7 checkboxes, 8 Apply, 9 Cancel
        JR Z, .WaitKey 
        
        LD (OldSelectedOption), A         
        INC A
        LD (SelectedOption), A
        CALL UpdateFocus
        JR MainLoop

.NotDown:
        CP Keyboard.KEY_SELECT                 
        JR NZ, .WaitKey

        LD A, (SelectedOption)
        CP 8
        JR Z, ActionApply       
        CP 9
        JR Z, ActionCancel      

        ; Inverse a selected checkbox (0-7)
        LD C, A                 
        LD B, 1                 
        INC C
.ShiftLoop:
        DEC C
        JR Z, .ShiftDone
        SLA B                   
        JR .ShiftLoop
.ShiftDone:
        LD A, (CheckboxState)
        XOR B                   
        LD (CheckboxState), A
        LD A, (SelectedOption)
        CALL RedrawSingleCheckbox
        JR MainLoop

ActionApply:
        CALL Screen.Clear
        CALL Screen.ResetAttributes

        LD DE, SavingText
        LD BC, 0x0504 ; row 5, col 4
        CALL Screen.PrintString
        
        LD A, (CheckboxState)
        CALL MegaBuzz.ApplyConfig 

        CALL Screen.Clear
        CALL Screen.ResetAttributes

        LD DE, DoneText
        LD BC, 0x0504 ; row 5, col 4
        CALL Screen.PrintString

        JP Start

ActionCancel:

        CALL Screen.Clear
        CALL Screen.ResetAttributes

        LD DE, DoneText
        LD BC, 0x0504 ; row 5, col 4
        CALL Screen.PrintString

        CALL MegaBuzz.Cancel      
        JP Start

KeyDelay:
        LD BC, 0x3FFF       
.Loop:
        DEC BC
        LD A, B
        OR C
        JR NZ, .Loop
        RET

DrawStaticInterface:
        ;CALL Screen.ResetAttributes

        LD DE, TitleText
        LD BC, 0x0200 ; row 2, col 0
        CALL Screen.PrintString

        LD DE, Str_Help1
        LD BC, 0x1400 ; row 20, col 0
        CALL Screen.PrintString

        LD DE, Str_Help2
        LD BC, 0x1500 ; row 21, col 0
        CALL Screen.PrintString

        ; Checkboxes (Rows 5-12)
        XOR A               
        LD (CurrentStep), A
.LoopCB:
        LD A, (CurrentStep)
        LD C, 4             
        ADD A, 5            
        LD B, A             ; row 5-12
        
        PUSH BC
        CALL GetCBText
        CALL Screen.PrintString    
        POP BC

        LD A, C
        ADD A, 5
        LD C, A             ; Text offset

        LD A, (CurrentStep)
        CALL GetOptionTextAddress
        CALL Screen.PrintString

        LD A, (CurrentStep)
        INC A
        LD (CurrentStep), A
        CP 8                
        JR NZ, .LoopCB

        IFDEF DEBUG_MODE
        ; debug initial value
        LD DE, Str_DebugInit
        LD BC, 0x0E04       ; row 14, col 4
        CALL Screen.PrintString
        LD A, (InitialConfig)
        LD BC, 0x0E09       ; row 14, col 9
        CALL Screen.PrintHexByte

        ; debug current value
        LD DE, Str_DebugCurr
        LD BC, 0x0E12       ; row 14, col 18
        CALL Screen.PrintString
        LD A, (CheckboxState)
        LD BC, 0x0E17       ; row 14, col 23
        CALL Screen.PrintHexByte
        ENDIF

        ; Grey button bg (row 16)
        LD B, 16 : LD C, 4 : LD D, 9
        CALL Screen.ColorizeButtonDefault
        LD B, 16 : LD C, 18 : LD D, 10
        CALL Screen.ColorizeButtonDefault

        ; Buttons texts
        LD DE, Btn_Apply : LD BC, 0x1004 : CALL Screen.PrintString
        LD DE, Btn_Cancel : LD BC, 0x1012 : CALL Screen.PrintString

        ; Init default blue bg on first menu item
        LD B, 5 : LD C, 4 : LD D, 24
        CALL Screen.ColorizeHighlight
        RET

UpdateFocus:
        LD A, (OldSelectedOption)
        CP 8
        JR Z, .ClearApply
        CP 9
        JR Z, .ClearCancel
        
        ADD A, 5
        LD B, A : LD C, 4 : LD D, 24
        CALL Screen.ColorizeNormal
        JR .DrawNewFocus

.ClearApply:
        LD B, 16 : LD C, 4 : LD D, 9
        CALL Screen.ColorizeButtonDefault
        JR .DrawNewFocus

.ClearCancel:
        LD B, 16 : LD C, 18 : LD D, 10
        CALL Screen.ColorizeButtonDefault

.DrawNewFocus:
        LD A, (SelectedOption)
        CP 8
        JR Z, .SetApply
        CP 9
        JR Z, .SetCancel

        ADD A, 5
        LD B, A : LD C, 4 : LD D, 24
        CALL Screen.ColorizeHighlight
        RET
.SetApply:
        LD B, 16 : LD C, 4 : LD D, 9
        CALL Screen.ColorizeHighlight
        RET
.SetCancel:
        LD B, 16 : LD C, 18 : LD D, 10
        CALL Screen.ColorizeHighlight
        RET

RedrawSingleCheckbox:
        PUSH AF             
        LD (CurrentStep), A 
        ADD A, 5
        LD B, A             
        LD C, 4             
        CALL GetCBText      
        CALL Screen.PrintString

        IFDEF DEBUG_MODE        
        LD A, (CheckboxState)
        LD BC, 0x0E17       ; Row 14, Col 23 (CURR)
        CALL Screen.PrintHexByte
        ENDIF        

        POP AF              
        RET

GetCBText:
        LD A, (CurrentStep) 
        LD E, A
        INC E
        LD A, (CheckboxState)
.Loop:
        DEC E
        JR Z, .Done
        SRL A
        JR .Loop
.Done:
        AND 1
        LD DE, CB_Unselected
        RET Z
        LD DE, CB_Selected
        RET

GetOptionTextAddress:
        LD L, A
        LD H, 0
        ADD HL, HL          
        LD DE, OptionTexts
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        RET

; Text data
TitleText:       DB "--KARABAS MEGABUZZ CONFIG v1.0--", 0
LoadingText:     DB "Loading... please wait", 0
SavingText:      DB "Saving... please wait", 0
DoneText:        DB "Done! Safe to reboot", 0
CB_Unselected:   DB "[ ]", 0
CB_Selected:     DB "[x]", 0
Btn_Apply:       DB "  APPLY  ", 0
Btn_Cancel:      DB "  CANCEL  ", 0

Str_Opt1:        DB "Enable DivMMC ", 0
Str_Opt2:        DB "Enable ZC ", 0
Str_Opt3:        DB "Enable Soundrive ", 0
Str_Opt4:        DB "Enable Beeper ", 0
Str_Opt5:        DB "Enable SAA1099 ", 0
Str_Opt6:        DB "Enable GS ", 0
Str_Opt7:        DB "Enable TSFM / MIDI ", 0
Str_Opt8:        DB "Enable OPL3 ", 0

Str_DebugInit:   DB "INIT:#", 0
Str_DebugCurr:   DB "CURR:#", 0

Str_Help1:       DB "Please use UP/DOWN to navigate,", 0
Str_Help2:       DB "Use Enter or Space to change", 0

OptionTexts:
        DW Str_Opt1, Str_Opt2, Str_Opt3, Str_Opt4
        DW Str_Opt5, Str_Opt6, Str_Opt7, Str_Opt8

; Variables
SelectedOption: EQU 0x5C00  
CheckboxState:  EQU 0x5C01  
CurrentStep:    EQU 0x5C02
OldSelectedOption: EQU 0x5C03
InitialConfig:     EQU 0x5C04

; Expand ROM to 2KB
        IFDEF EMU_MODE
        BLOCK 16384-$, 0
        ELSE
        BLOCK 2048-$, 0
        ENDIF

