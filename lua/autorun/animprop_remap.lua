//This file contains a table of bone names, used by remapping to automatically translate between (buman/biped character model) skeletons with different names for the same bones.
//Each subtable is formatted as a list of equivalent bones in the exact same order, with an empty string when the skeleton doesn't have any equivalent to the standard HL2/TF2 biped skeletons.
//The function that reads this table works by checking each subtable and counting how many listed bone names match the ones on the model. The one with the highest count is used for the model, and in the case 
//of a tie, the subtable earlier in the table is used. This means that weird variants like the HL2 Alternate one below should be HIGHER in the table than the standard skeleton.

AddCSLuaFile()
if CLIENT then return end
Animprop_RemapTranslationSkeletons = {




//HL2 Human Alternate (cheaple.mdl, corpse1.mdl, classic_legs.mdl, fast.mdl, poison.mdl, fast_torso.mdl, zombie_soldier_legs/torso.mdl, soldier_stripped.mdl)
//This is a variant of the HL2 skeleton where the root bone is called "ValveBiped.Bip01" instead of "ValveBiped.Bip01_Pelvis".
//Check for this FIRST, because some models that use this skeleton (classic_legs.mdl, fast.mdl, fast_torso.mdl, zombie_soldier_legs/torso.mdl, soldier_stripped.mdl) ALSO have a ValveBiped.Bip01_Pelvis
//that's just a helper bone and shouldn't be remapped.
//Ep2 skeleton models are the exception to this rule - they have Bip01 and Bip01_Pelvis, but the latter is the actual root bone - but they're not as important since Gmod comes with a better one as a playermodel.
{
"ValveBiped.Bip01", //the only difference between this and regular HL2 is that ValveBiped.Bip01_Pelvis is named this instead
"ValveBiped.Bip01_Spine",
"ValveBiped.Bip01_Spine1",
"ValveBiped.Bip01_Spine2",
"ValveBiped.Bip01_Spine4", //yes, skipping Spine3 is standard, haven't found a single model using this skeleton with a Spine3
"ValveBiped.Bip01_Neck1",
"ValveBiped.Bip01_Head1",

"ValveBiped.Bip01_L_Clavicle",
"ValveBiped.Bip01_L_UpperArm",
"ValveBiped.Bip01_L_Forearm",
"ValveBiped.Bip01_L_Hand",

"ValveBiped.Bip01_R_Clavicle",
"ValveBiped.Bip01_R_UpperArm",
"ValveBiped.Bip01_R_Forearm",
"ValveBiped.Bip01_R_Hand",

"ValveBiped.Bip01_L_Thigh",
"ValveBiped.Bip01_L_Calf",
"ValveBiped.Bip01_L_Foot",
"ValveBiped.Bip01_L_Toe0",

"ValveBiped.Bip01_R_Thigh",
"ValveBiped.Bip01_R_Calf",
"ValveBiped.Bip01_R_Foot",
"ValveBiped.Bip01_R_Toe0",

"ValveBiped.Bip01_L_Finger4",
"ValveBiped.Bip01_L_Finger41",
"ValveBiped.Bip01_L_Finger42",
"ValveBiped.Bip01_L_Finger3",
"ValveBiped.Bip01_L_Finger31",
"ValveBiped.Bip01_L_Finger32",
"ValveBiped.Bip01_L_Finger2",
"ValveBiped.Bip01_L_Finger21",
"ValveBiped.Bip01_L_Finger22",
"ValveBiped.Bip01_L_Finger1",
"ValveBiped.Bip01_L_Finger11",
"ValveBiped.Bip01_L_Finger12",
"ValveBiped.Bip01_L_Finger0",
"ValveBiped.Bip01_L_Finger01",
"ValveBiped.Bip01_L_Finger02",

"ValveBiped.Bip01_R_Finger4",
"ValveBiped.Bip01_R_Finger41",
"ValveBiped.Bip01_R_Finger42",
"ValveBiped.Bip01_R_Finger3",
"ValveBiped.Bip01_R_Finger31",
"ValveBiped.Bip01_R_Finger32",
"ValveBiped.Bip01_R_Finger2",
"ValveBiped.Bip01_R_Finger21",
"ValveBiped.Bip01_R_Finger22",
"ValveBiped.Bip01_R_Finger1",
"ValveBiped.Bip01_R_Finger11",
"ValveBiped.Bip01_R_Finger12",
"ValveBiped.Bip01_R_Finger0",
"ValveBiped.Bip01_R_Finger01",
"ValveBiped.Bip01_R_Finger02",
},




//HL2 Human / Gmod Player / CSS Player/Hostage / L4D2 Survivor(? tested with mods only, not models from game)
{
"ValveBiped.Bip01_Pelvis",
"ValveBiped.Bip01_Spine",
"ValveBiped.Bip01_Spine1",
"ValveBiped.Bip01_Spine2",
"ValveBiped.Bip01_Spine4", //yes, skipping Spine3 is standard, haven't found a single model using this skeleton with a Spine3
"ValveBiped.Bip01_Neck1",
"ValveBiped.Bip01_Head1",

"ValveBiped.Bip01_L_Clavicle",
"ValveBiped.Bip01_L_UpperArm",
"ValveBiped.Bip01_L_Forearm",
"ValveBiped.Bip01_L_Hand",

"ValveBiped.Bip01_R_Clavicle",
"ValveBiped.Bip01_R_UpperArm",
"ValveBiped.Bip01_R_Forearm",
"ValveBiped.Bip01_R_Hand",

"ValveBiped.Bip01_L_Thigh",
"ValveBiped.Bip01_L_Calf",
"ValveBiped.Bip01_L_Foot",
"ValveBiped.Bip01_L_Toe0",

"ValveBiped.Bip01_R_Thigh",
"ValveBiped.Bip01_R_Calf",
"ValveBiped.Bip01_R_Foot",
"ValveBiped.Bip01_R_Toe0",

"ValveBiped.Bip01_L_Finger4",
"ValveBiped.Bip01_L_Finger41",
"ValveBiped.Bip01_L_Finger42",
"ValveBiped.Bip01_L_Finger3",
"ValveBiped.Bip01_L_Finger31",
"ValveBiped.Bip01_L_Finger32",
"ValveBiped.Bip01_L_Finger2",
"ValveBiped.Bip01_L_Finger21",
"ValveBiped.Bip01_L_Finger22",
"ValveBiped.Bip01_L_Finger1",
"ValveBiped.Bip01_L_Finger11",
"ValveBiped.Bip01_L_Finger12",
"ValveBiped.Bip01_L_Finger0",
"ValveBiped.Bip01_L_Finger01",
"ValveBiped.Bip01_L_Finger02",

"ValveBiped.Bip01_R_Finger4",
"ValveBiped.Bip01_R_Finger41",
"ValveBiped.Bip01_R_Finger42",
"ValveBiped.Bip01_R_Finger3",
"ValveBiped.Bip01_R_Finger31",
"ValveBiped.Bip01_R_Finger32",
"ValveBiped.Bip01_R_Finger2",
"ValveBiped.Bip01_R_Finger21",
"ValveBiped.Bip01_R_Finger22",
"ValveBiped.Bip01_R_Finger1",
"ValveBiped.Bip01_R_Finger11",
"ValveBiped.Bip01_R_Finger12",
"ValveBiped.Bip01_R_Finger0",
"ValveBiped.Bip01_R_Finger01",
"ValveBiped.Bip01_R_Finger02",
},




//HL2 Vortigaunt
{
"ValveBiped.hips",
"ValveBiped.spine1",
"ValveBiped.spine2",
"ValveBiped.spine3",
"ValveBiped.spine4",
"ValveBiped.neck1", //ValveBiped.neck2
"ValveBiped.head",

"ValveBiped.clavical_L",
"ValveBiped.arm1_L",
"ValveBiped.arm2_L",
"ValveBiped.hand1_L",

"ValveBiped.clavical_R",
"ValveBiped.arm1_R",
"ValveBiped.arm2_R",
"ValveBiped.hand1_R",

"ValveBiped.leg_bone1_L",
"ValveBiped.leg_bone2_L", //ValveBiped.leg_bone3_L //vorts have digitigrade legs with an extra bone so they don't translate well, but this one tends to have a better angle most of the time
"ValveBiped.Bip01_L_Foot",
"ValveBiped.Bip01_L_Toe0",

"ValveBiped.leg_bone1_R",
"ValveBiped.leg_bone2_R", //ValveBiped.leg_bone3_R
"ValveBiped.Bip01_R_Foot",
"ValveBiped.Bip01_R_Toe0",

"ValveBiped.pinky1_L",
"ValveBiped.pinky2_L",
"ValveBiped.pinky3_L",
"", //TODO: should we fill this in with other bone names just in case there's weird beta models or something using this same convention?
"",
"",
"",
"",
"",
"ValveBiped.index1_L",
"ValveBiped.index2_L",
"ValveBiped.index3_L",
"",
"",
"",

"ValveBiped.pinky1_R",
"ValveBiped.pinky2_R",
"ValveBiped.pinky3_R",
"",
"",
"",
"",
"",
"",
"ValveBiped.index1_R",
"ValveBiped.index2_R",
"ValveBiped.index3_R",
"",
"",
"",
},




//HL2 Dog
{
"Dog_Model.Pelvis",
"Dog_Model.Spine1",
"Dog_Model.Spine2",
"Dog_Model.Spine3",
"",
"Dog_Model.Neck2", //Dog_Model.Neck1, Dog_Model.Neck1_Length, Dog_Model.Neck2_Length
"Dog_Model.Eye",

"Dog_Model.Clavical_L",
"Dog_Model.Arm1_L",
"Dog_Model.Arm2_L",
"Dog_Model.Hand_L",

"Dog_Model.Clavical_R",
"Dog_Model.Arm1_R",
"Dog_Model.Arm2_R",
"Dog_Model.Hand_R", //Dog_Model.Hand_R_Drill

"Dog_Model.Leg1_L",
"Dog_Model.Leg2_L",
"Dog_Model.Foot_L",
"Dog_Model.Toe_L", //Dog_Model.phalanges_L

"Dog_Model.Leg1_R",
"Dog_Model.Leg2_R",
"Dog_Model.Foot_R",
"Dog_Model.Toe_R",

"Dog_Model.Pinky1_L",
"Dog_Model.Pinky2_L",
"Dog_Model.Pinky3_L",
"",
"",
"",
"",
"",
"",
"Dog_Model.Index1_L",
"Dog_Model.Index2_L",
"Dog_Model.Index3_L",
"Dog_Model.Thumb1_L",
"Dog_Model.Thumb2_L",
"", //no thumb3_L

"Dog_Model.Pinky1_R",
"Dog_Model.Pinky2_R",
"Dog_Model.Pinky3_R",
"",
"",
"",
"",
"",
"",
"Dog_Model.Index1_R",
"Dog_Model.Index2_R",
"Dog_Model.Index3_R",
"Dog_Model.Thumb1_R",
"Dog_Model.Thumb2_R",
"Dog_Model.Thumb3_R",
},




//TF2 Player
{
"bip_pelvis",
"bip_spine_0",
"bip_spine_1",
"bip_spine_2",
"bip_spine_3",
"bip_neck",
"bip_head",

"bip_collar_L",
"bip_upperArm_L",
"bip_lowerArm_L",
"bip_hand_L",

"bip_collar_R",
"bip_upperArm_R",
"bip_lowerArm_R",
"bip_hand_R",

"bip_hip_L",
"bip_knee_L",
"bip_foot_L",
"bip_toe_L",

"bip_hip_R",
"bip_knee_R",
"bip_foot_R",
"bip_toe_R",

"bip_pinky_0_L",
"bip_pinky_1_L",
"bip_pinky_2_L",
"bip_ring_0_L",
"bip_ring_1_L",
"bip_ring_2_L",
"bip_middle_0_L",
"bip_middle_1_L",
"bip_middle_2_L",
"bip_index_0_L",
"bip_index_1_L",
"bip_index_2_L",
"bip_thumb_0_L",
"bip_thumb_1_L",
"bip_thumb_2_L",

"bip_pinky_0_R",
"bip_pinky_1_R",
"bip_pinky_2_R",
"bip_ring_0_R",
"bip_ring_1_R",
"bip_ring_2_R",
"bip_middle_0_R",
"bip_middle_1_R",
"bip_middle_2_R",
"bip_index_0_R",
"bip_index_1_R",
"bip_index_2_R",
"bip_thumb_0_R",
"bip_thumb_1_R",
"bip_thumb_2_R",
},




//HL1 Barney/Gman/Zombie/Hgrunt/Assassin/Holo/Vort/Agrunt/Controller/Garg
{
"Bip01 Pelvis",
"Bip01 Spine",
"Bip01 Spine1",
"Bip01 Spine2",
"Bip01 Spine3",
"Bip01 Neck",
"Bip01 Head",

"Bip01 L Arm",
"Bip01 L Arm1",
"Bip01 L Arm2",
"Bip01 L Hand",

"Bip01 R Arm",
"Bip01 R Arm1",
"Bip01 R Arm2",
"Bip01 R Hand",

"Bip01 L Leg",
"Bip01 L Leg1",
"Bip01 L Foot",
"Bip01_L_Toe0", //only assassin/holo/vort/agrunt/controller/garg have toe bones

"Bip01 R Leg",
"Bip01 R Leg1",
"Bip01 R Foot",
"Bip01_R_Toe0",

"Bip01 L Finger0",  //only gman/zombie/holo/vort/controller have finger bones, and only some of them, but we'll list them all just in case there's more detailed models
"Bip01 L Finger01",
"Bip01 L Finger02",
"Bip01 L Finger1",
"Bip01 L Finger11",
"Bip01 L Finger12",
"Bip01 L Finger2",
"Bip01 L Finger21",
"Bip01 L Finger22",
"Bip01 L Finger3",
"Bip01 L Finger31",
"Bip01 L Finger32",
"Bip01 L Finger4",
"Bip01 L Finger41",
"Bip01 L Finger42",

"Bip01 R Finger0",
"Bip01 R Finger01",
"Bip01 R Finger02",
"Bip01 R Finger1",
"Bip01 R Finger11",
"Bip01 R Finger12",
"Bip01 R Finger2",
"Bip01 R Finger21",
"Bip01 R Finger22",
"Bip01 R Finger3",
"Bip01 R Finger31",
"Bip01 R Finger32",
"Bip01 R Finger4",
"Bip01 R Finger41",
"Bip01 R Finger42",
},




//HL1 Scientist
{
"Bip02 Pelvis",
"Bip02 Spine",
"Bip02 Spine1",
"Bip02 Spine2",
"Bip02 Spine3", //scientist doesn't have more spine bones, but included anyway just in case there's more detailed models using same skeleton
"Bip02 Neck",
"Bip02 Head",

"Bip02 L Arm",
"Bip02 L Arm1",
"Bip02 L Arm2",
"Bip02 L Hand",

"Bip02 R Arm",
"Bip02 R Arm1",
"Bip02 R Arm2",
"Bip02 R Hand",

"Bip02 L Leg",
"Bip02 L Leg1",
"Bip02 L Foot",
"Bip01_L_Toe0", //scientist doesn't have toe bones, but included anyway

"Bip02 R Leg",
"Bip02 R Leg1",
"Bip02 R Foot",
"Bip01_R_Toe0", //scientist doesn't have toe bones, but included anyway

"Bip02 L Finger0",  //scientist doesn't have finger bones, but included anyway
"Bip02 L Finger01",
"Bip02 L Finger02",
"Bip02 L Finger1",
"Bip02 L Finger11",
"Bip02 L Finger12",
"Bip02 L Finger2",
"Bip02 L Finger21",
"Bip02 L Finger22",
"Bip02 L Finger3",
"Bip02 L Finger31",
"Bip02 L Finger32",
"Bip02 L Finger4",
"Bip02 L Finger41",
"Bip02 L Finger42",

"Bip02 R Finger0",
"Bip02 R Finger01",
"Bip02 R Finger02",
"Bip02 R Finger1",
"Bip02 R Finger11",
"Bip02 R Finger12",
"Bip02 R Finger2",
"Bip02 R Finger21",
"Bip02 R Finger22",
"Bip02 R Finger3",
"Bip02 R Finger31",
"Bip02 R Finger32",
"Bip02 R Finger4",
"Bip02 R Finger41",
"Bip02 R Finger42",
},




} //end of table
//TODO: Portal, Portal 2, L4D, L4D2, CS:GO, whatever other mountable games people will want to use (fingerposer code says insurgency has its own skeleton naming conventions)