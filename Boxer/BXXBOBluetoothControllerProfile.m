//
//  BXXBOBluetoothControllerProfile.m
//  Boxer
//
//  Created by C.W. Betts on 7/11/18.
//  Copyright © 2018 Alun Bestor and contributors. All rights reserved.
//

#import "BXHIDControllerProfilePrivate.h"
#import "DDHidUsage+ADBUsageExtensions.h"
#import "BXSession+BXUIControls.h"

@interface BXXBOBluetoothControllerProfile: BXHIDControllerProfile
@end

NS_ENUM(unsigned int) {
    BXXBOBTControllerLeftStickX       = 0x01 << 16 | kHIDUsage_GD_X,
    BXXBOBTControllerLeftStickY       = 0x01 << 16 | kHIDUsage_GD_Y,
    BXXBOBTControllerRightStickX      = 0x01 << 16 | kHIDUsage_GD_Z,
    BXXBOBTControllerRightStickY      = 0x01 << 16 | kHIDUsage_GD_Rz,
    BXXBOBTControllerLeftTrigger      = 0x02 << 16 | kHIDUsage_Sim_Brake,
    BXXBOBTControllerRightTrigger     = 0x02 << 16 | kHIDUsage_Sim_Accelerator
};

NS_ENUM(unsigned int) {
    BXXBOBTControllerAButton = 0x09 << 16 | kHIDUsage_Button_1,
    BXXBOBTControllerBButton,
    BXXBOBTControllerXButton = 0x09 << 16 | kHIDUsage_Button_4,
    BXXBOBTControllerYButton,
    
    BXXBOBTControllerLeftShoulder = 0x09 << 16 | (kHIDUsage_Button_1 + 6),
    BXXBOBTControllerRightShoulder,
    
    BXXBOBTControllerLeftStickClick = 0x09 << 16 | (kHIDUsage_Button_1 + 13),
    BXXBOBTControllerRightStickClick,
    
    BXXBOBTControllerStartButton  = 0x09 << 16 | (kHIDUsage_Button_1 + 11),
    BXXBOBTControllerBackButton   = 0x0C << 16 | kHIDUsage_Csmr_ACBack,
    BXXBOBTControllerXBoxButton   = 0x0C << 16 | kHIDUsage_Csmr_ACHome,
    
    BXXBOBTControllerDPadUp       = 0x01 << 16 | kHIDUsage_GD_Hatswitch,
    BXXBOBTControllerDPadDown     = 0x01 << 16 | kHIDUsage_GD_Hatswitch,
    BXXBOBTControllerDPadLeft     = 0x01 << 16 | kHIDUsage_GD_Hatswitch,
    BXXBOBTControllerDPadRight    = 0x01 << 16 | kHIDUsage_GD_Hatswitch
};


@implementation BXXBOBluetoothControllerProfile

+ (void) load
{
    [BXHIDControllerProfile registerProfile: self];
}

+ (NSArray *) matchedIDs
{
    return @[[self matchForVendorID: 0x045E
                          productID: 0x02FD]];
}

- (BXControllerStyle) controllerStyle { return BXControllerStyleGamepad; }

//Custom binding for 360 shoulder buttons: bind to buttons 3 & 4 for regular joysticks
//(where the triggers are buttons 1 & 2), or to 1 & 2 for wheel emulation (where the
//triggers are the pedals).
- (id <BXHIDInputBinding>) generatedBindingForButtonElement: (DDHidElement *)element
{
    id <BXHIDInputBinding> binding = nil;
    BOOL isWheel =    [self.emulatedJoystick conformsToProtocol: @protocol(BXEmulatedWheel)];
    
    switch (element.usage.usagePage << 16 | element.usage.usageId)
    {
        case BXXBOBTControllerLeftShoulder:
            binding = [self bindingFromButtonElement: element
                                            toButton: (isWheel ? BXEmulatedJoystickButton2 : BXEmulatedJoystickButton4)];
            break;
            
        case BXXBOBTControllerRightShoulder:
            binding = [self bindingFromButtonElement: element
                                            toButton: (isWheel ? BXEmulatedJoystickButton1 : BXEmulatedJoystickButton3)];
            break;
            
        case BXXBOBTControllerBackButton:
            binding = [self bindingFromButtonElement: element toKeyCode: KBD_esc];
            break;
            
        case BXXBOBTControllerStartButton:
            binding = [self bindingFromButtonElement: element toTarget: nil action: @selector(togglePaused:)];
            break;
            
        case BXXBOBTControllerXButton:
            binding = [self bindingFromButtonElement: element
                                            toButton: BXEmulatedJoystickButton3];
            break;

        case BXXBOBTControllerYButton:
            binding = [self bindingFromButtonElement: element
                                            toButton: BXEmulatedJoystickButton4];
            break;

        case BXXBOBTControllerLeftStickClick:
            binding = [self bindingFromButtonElement: element
                                            toButton: BXCHCombatStickButton5];
            break;

        case BXXBOBTControllerRightStickClick:
            binding = [self bindingFromButtonElement: element
                                            toButton: BXCHCombatStickButton6];
            break;
            
        default:
            binding = [super generatedBindingForButtonElement: element];
    }
    
    return binding;
}

//Bind triggers to buttons 1 & 2 for regular joystick emulation.
- (id <BXHIDInputBinding>) generatedBindingForAxisElement: (DDHidElement *)element
{
    id <BXHIDInputBinding> binding = nil;
    
    switch (element.usage.usagePage << 16 | element.usage.usageId)
    {
        case BXXBOBTControllerLeftTrigger:
            binding = [self bindingFromTriggerElement: element toButton: BXEmulatedJoystickButton2];
            break;
            
        case BXXBOBTControllerRightTrigger:
            binding = [self bindingFromTriggerElement: element toButton: BXEmulatedJoystickButton1];
            break;
            
        default:
            binding = [super generatedBindingForAxisElement: element];
    }
    return binding;
}

//Bind triggers to brake/accelerator for wheel emulation.
- (void) bindAxisElementsForWheel:(NSArray<DDHidElement *> *)elements
{
    for (DDHidElement *element in elements)
    {
        id <BXHIDInputBinding> binding;
        switch (element.usage.usagePage << 16 | element.usage.usageId)
        {
            case BXXBOBTControllerLeftStickX:
                binding = [self bindingFromAxisElement: element toAxis: BXAxisWheel];
                break;
                
            case BXXBOBTControllerRightStickY:
                binding = [self bindingFromAxisElement: element
                                        toPositiveAxis: BXAxisBrake
                                          negativeAxis: BXAxisAccelerator];
                break;
                
            case BXXBOBTControllerLeftTrigger:
                binding = [self bindingFromTriggerElement: element toAxis: BXAxisBrake];
                break;
                
            case BXXBOBTControllerRightTrigger:
                binding = [self bindingFromTriggerElement: element toAxis: BXAxisAccelerator];
                break;
                
            default:
                binding = nil;
        }
        
        if (binding)
            [self setBinding: binding forElement: element];
    }
}

@end
