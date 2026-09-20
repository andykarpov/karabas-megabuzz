; =============================================================================
; Karabas MegaBuzz Configurator ROM
; main entry point
; =============================================================================

        DEVICE ZXSPECTRUM48
        OUTPUT "megabuzz.rom"

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

        ; Selected option = 0
        XOR A
        LD (SelectedOption), A  

        ; Read MegaBuzz config byte
        XOR A
        CALL MegaBuzz.ReadConfig
        LD (CheckboxState), A   

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
        LD A, (CheckboxState)
        JP MegaBuzz.ApplyConfig 

ActionCancel:
        JP MegaBuzz.Cancel      

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
        LD (CurrentStep), A
        ADD A, 5
        LD B, A
        LD C, 4             ; checkbox coord on the screen
        
        CALL GetCBText      ; Returns DE = row address "[ ]" or "[X]"
        CALL Screen.PrintString
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

OptionTexts:
        DW Str_Opt1, Str_Opt2, Str_Opt3, Str_Opt4
        DW Str_Opt5, Str_Opt6, Str_Opt7, Str_Opt8

; Variables
SelectedOption: EQU 0x5C00  
CheckboxState:  EQU 0x5C01  
CurrentStep:    EQU 0x5C02
OldSelectedOption: EQU 0x5C03

; Expand ROM to 2KB
        BLOCK 2048-$, 0
        ;BLOCK 16384-$, 0

