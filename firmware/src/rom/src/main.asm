; =============================================================================
; Karabas MegaBuzz Configurator ROM
; main entry point
; =============================================================================

;        DEFINE DEBUG_MODE
;        DEFINE EMU_MODE

        DEVICE ZXSPECTRUM48
;        OUTPUT "megabuzz.rom"

        ORG 0x0000

; UI constants
NUM_CHECKBOXES  EQU 11                              ; count of checkboxes
INDEX_APPLY     EQU NUM_CHECKBOXES                  ; Apply button index
INDEX_CANCEL    EQU NUM_CHECKBOXES + 1              ; Cancel button index
BUTTONS_ROW     EQU 5 + NUM_CHECKBOXES + 2          ; buttons row
DEBUG_ROW       EQU BUTTONS_ROW + 2                 ; debug info row

Start:
        DI
        LD SP, 0xBD00       ; Init safe stack

        JP RealStart

        INCLUDE "screen.asm"
        INCLUDE "megabuzz.asm"
        INCLUDE "keyboard.asm"

RealStart:
        CALL Screen.Clear : CALL Screen.ResetAttributes
        LD DE, LoadingText : LD BC, 0x0504 : CALL Screen.PrintString
        XOR A : LD (SelectedOption), A : LD (CheckboxState), A : LD (CheckboxState2), A
        CALL MegaBuzz.WaitFlash
        CALL Screen.Clear : CALL Screen.ResetAttributes
        CALL MegaBuzz.WaitFlash
        CALL MegaBuzz.ReadConfig : LD (CheckboxState), A
        CALL MegaBuzz.WaitFlash
        CALL MegaBuzz.ReadConfig2 : LD (CheckboxState2), A
        CALL MegaBuzz.WaitFlash
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
        CP INDEX_CANCEL
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
        CP INDEX_APPLY
        JR Z, ActionApply       
        CP INDEX_CANCEL
        JR Z, ActionCancel      

        LD A, (SelectedOption)
        CP 8
        JR NC, .BitInState2

        LD C, A                 
        LD B, 1                 
        INC C
.ShiftLoop1:
        DEC C
        JR Z, .ShiftDone1
        SLA B                   
        JR .ShiftLoop1
.ShiftDone1:
        LD A, (CheckboxState)
        XOR B                   
        LD (CheckboxState), A
        JR .Redraw

.BitInState2:
        SUB 8
        LD C, A                 
        LD B, 1                 
        INC C
.ShiftLoop2:
        DEC C
        JR Z, .ShiftDone2
        SLA B                   
        JR .ShiftLoop2
.ShiftDone2:
        LD A, (CheckboxState2)
        XOR B                   
        LD (CheckboxState2), A

.Redraw:
        LD A, (SelectedOption)
        CALL RedrawSingleCheckbox
        JR MainLoop

ActionApply:
        CALL Screen.Clear : CALL Screen.ResetAttributes
        LD DE, SavingText : LD BC, 0x0504 : CALL Screen.PrintString        
        LD A, (CheckboxState) : CALL MegaBuzz.ApplyConfig
        LD A, (CheckboxState2) : CALL MegaBuzz.ApplyConfig2

ActionCancel:
        CALL Screen.Clear : CALL Screen.ResetAttributes
        LD DE, DoneText : LD BC, 0x0504 : CALL Screen.PrintString

        ;CALL MegaBuzz.Cancel   
        ;LD SP, 0xFFFF : JP 0x0000

        ; Copy executable code into ram at 0x8000 and execute it
        LD HL, RelocatableCode_Start
        LD DE, 0x8000
        LD BC, RelocatableCode_End - RelocatableCode_Start
        LDIR
        JP 0x8000

RelocatableCode_Start:
        ; disable cfg rom
        ld a, MegaBuzz.REG_ROMBANK : ld bc, MegaBuzz.PORT_ZXUNO_REG : out (c), a
        xor a : ld bc, MegaBuzz.PORT_ZXUNO_DATA : out (c), a
        ; jump to ZX ROM start
        LD SP, 0xFFFF : JP #0000
RelocatableCode_End:

KeyDelay:
        LD BC, 0x3FFF       
.Loop:
        DEC BC
        LD A, B
        OR C
        JR NZ, .Loop
        RET

DrawStaticInterface:
        LD DE, TitleText : LD BC, 0x0200 : CALL Screen.PrintString

        IFDEF EMU_MODE
        LD DE, Str_Help1 : LD BC, 0x1600 : CALL Screen.PrintString
        LD DE, Str_Help2 : LD BC, 0x1700 : CALL Screen.PrintString
        ENDIF

        ; Checkboxes (rows 5 и далее)
        XOR A : LD (CurrentStep), A
.LoopCB:
        LD A, (CurrentStep)
        LD C, 4             
        ADD A, 5            
        LD B, A             ; row 5+
        
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
        CP NUM_CHECKBOXES
        JR NZ, .LoopCB

        IFDEF DEBUG_MODE
        LD DE, Str_DebugCurr
        LD B, DEBUG_ROW : LD C, 4
        CALL Screen.PrintString
        LD A, (CheckboxState2)
        LD B, DEBUG_ROW : LD C, 9
        CALL Screen.PrintHexByte
        LD A, (CheckboxState)
        LD B, DEBUG_ROW : LD C, 11
        CALL Screen.PrintHexByte
        ENDIF

        LD B, BUTTONS_ROW : LD C, 4 : LD D, 9
        CALL Screen.ColorizeButtonDefault
        LD B, BUTTONS_ROW : LD C, 18 : LD D, 10
        CALL Screen.ColorizeButtonDefault

        LD DE, Btn_Apply : LD B, BUTTONS_ROW : LD C, 4 : CALL Screen.PrintString
        LD DE, Btn_Cancel : LD B, BUTTONS_ROW : LD C, 18 : CALL Screen.PrintString

        LD B, 5 : LD C, 4 : LD D, 24
        CALL Screen.ColorizeHighlight
        RET

UpdateFocus:
        LD A, (OldSelectedOption)
        CP INDEX_APPLY
        JR Z, .ClearApply
        CP INDEX_CANCEL
        JR Z, .ClearCancel
        
        ADD A, 5
        LD B, A : LD C, 4 : LD D, 24
        CALL Screen.ColorizeNormal
        JR .DrawNewFocus

.ClearApply:
        LD B, BUTTONS_ROW : LD C, 4 : LD D, 9
        CALL Screen.ColorizeButtonDefault
        JR .DrawNewFocus

.ClearCancel:
        LD B, BUTTONS_ROW : LD C, 18 : LD D, 10
        CALL Screen.ColorizeButtonDefault

.DrawNewFocus:
        LD A, (SelectedOption)
        CP INDEX_APPLY
        JR Z, .SetApply
        CP INDEX_CANCEL
        JR Z, .SetCancel

        ADD A, 5
        LD B, A : LD C, 4 : LD D, 24
        CALL Screen.ColorizeHighlight
        RET
.SetApply:
        LD B, BUTTONS_ROW : LD C, 4 : LD D, 9
        CALL Screen.ColorizeHighlight
        RET
.SetCancel:
        LD B, BUTTONS_ROW : LD C, 18 : LD D, 10
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
        LD A, (CheckboxState2)
        LD B, DEBUG_ROW : LD C, 9
        CALL Screen.PrintHexByte
        LD A, (CheckboxState)
        LD B, DEBUG_ROW : LD C, 11
        CALL Screen.PrintHexByte
        ENDIF        

        POP AF              
        RET

GetCBText:
        LD A, (CurrentStep) 
        CP 8
        JR NC, .GetFromState2

        LD E, A
        INC E
        LD A, (CheckboxState)
.Loop1:
        DEC E
        JR Z, .Done
        SRL A
        JR .Loop1

.GetFromState2:
        SUB 8
        LD E, A
        INC E
        LD A, (CheckboxState2)
.Loop2:
        DEC E
        JR Z, .Done
        SRL A
        JR .Loop2

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
TitleText:       DB "  KARABAS MEGABUZZ CONFIG v1.3  ", 0
LoadingText:     DB "Loading...", 0
SavingText:      DB "Saving...", 0
DoneText:        DB "Done! Safe to reboot", 0
CB_Unselected:   DB "[ ]", 0
CB_Selected:     DB "[x]", 0
Btn_Apply:       DB "  APPLY  ", 0
Btn_Cancel:      DB "  CANCEL  ", 0

; Options
Str_Opt1:        DB "DivMMC ", 0
Str_Opt2:        DB "ZC ", 0
Str_Opt3:        DB "Soundrive ", 0
Str_Opt4:        DB "Beeper ", 0
Str_Opt5:        DB "SAA1099 ", 0
Str_Opt6:        DB "GS ", 0
Str_Opt7:        DB "TSFM / MIDI ", 0
Str_Opt8:        DB "OPL3 ", 0
Str_Opt9:        DB "VU bar", 0
Str_Opt10:       DB "VU dot", 0
Str_Opt11:       DB "VU reversed", 0

    IFDEF DEBUG_MODE
Str_DebugCurr:   DB "VAL: #", 0
    ENDIF

    IFDEF EMU_MODE
Str_Help1:       DB "Please use UP/DOWN to navigate,", 0
Str_Help2:       DB "Use Enter or Space to change", 0
    ENDIF

OptionTexts:
        DW Str_Opt1, Str_Opt2, Str_Opt3, Str_Opt4
        DW Str_Opt5, Str_Opt6, Str_Opt7, Str_Opt8
        DW Str_Opt9, Str_Opt10, Str_Opt11

; Variables
SelectedOption:    EQU 0x5C00  
CheckboxState:     EQU 0x5C01
CheckboxState2:    EQU 0x5C02  
CurrentStep:       EQU 0x5C03
OldSelectedOption: EQU 0x5C04

; Expand ROM to 2KB
        IFDEF EMU_MODE
        BLOCK 16384-$, 0
        ELSE
        BLOCK 2048-$, 0
        ENDIF

