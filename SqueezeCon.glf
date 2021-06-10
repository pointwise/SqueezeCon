#############################################################################
#
# (C) 2021 Cadence Design Systems, Inc. All rights reserved worldwide.
#
# This sample script is not supported by Cadence Design Systems, Inc.
# It is provided freely for demonstration purposes only.
# SEE THE WARRANTY DISCLAIMER AT THE BOTTOM OF THIS FILE.
#
#############################################################################

#############################################################################
##
## squeezeCon.glf
##
## COPY CONNECTOR AND SCALE TO FIT BETWEEN TWO POINTS
## 
## Allows you to copy a connector and specify the desired final endpoints.
## 0. Choose connector (can be done prior to executing the script)
## 1. Choose first point for beginning of new connector
## 2. Choose second point for end of new connector
##
## Replaces two-step (multi-click) process of 1) Copy-Paste-Translate, Accept, 
## and 2) Edit-Transform-Scale. Script is necessary since the endpoint of the  
## temporary translated connector in the paste mode is not a pickable point. 
## Also, this script will take account for planar curves scaled in 3D, which
## is not handled by the scale operation alone.
## 
## As a general rule, avoid scaling arcs that define >90 degrees of a circle.
## 
#############################################################################

package require PWI_Glyph 2

## Select single connector to copy, translate and scale
proc selectCon {} {
    ## Set Info label
    set text1 "Please select connector to copy."
    ## Set selection mask
    set mask [pw::Display createSelectionMask -requireConnector {}]
    
    ###############################################
    ## This script uses the getSelectedEntities command added in 17.2R2
    ## Catch statement should check for previous versions
    if { [catch {pw::Display getSelectedEntities -selectionmask $mask curSelection}] } {
        set picked [pw::Display selectEntities -description $text1 -single\
            -selectionmask $mask curSelection]
        
        if {!$picked} {
            puts "Script aborted."
            exit
        }
    } elseif { [llength $curSelection(Connectors)] > 1 } {
        puts "Please select one connector."
        exit
    } elseif { [llength $curSelection(Connectors)] == 0 } {
        set picked [pw::Display selectEntities -description $text1 -single\
            -selectionmask $mask curSelection]
        
        if {!$picked} {
            puts "Script aborted."
            exit
        }
    }
    ###############################################
    
    return $curSelection(Connectors)
}

## Copy, Paste, Translate, and Scale selected connector to fit specified points
## Scale was used in place of stretch for more stable behavior, particularly 
## for circular arcs.
proc squeezeCon {con} {

    if { [catch {set pt2 [pw::Display selectPoint -description \
        "Select first point." -connector [list]]}]} {

        puts "Script aborted."
        exit
    }
    
    if { [catch {set pt3 [pw::Display selectPoint -description \
        "Select second point." -connector [list]]}]} {

        puts "Script aborted."
        exit
    }
    
    ## Find end of connector closest to the first point picked
    set pt1_a [$con getXYZ -arc 0.0]
    set pt1_b [$con getXYZ -arc 1.0]
    set diff_a [pwu::Vector3 length [pwu::Vector3 subtract $pt1_a $pt2]]
    set diff_b [pwu::Vector3 length [pwu::Vector3 subtract $pt1_b $pt2]]
    if {$diff_a <= $diff_b} {
        set pt1 $pt1_a
    } else {
        set pt1 $pt1_b
    }
    
    ## Define translation vector
    set transVec [pwu::Vector3 subtract $pt2 $pt1]
    
    ## Find out whether or not the connector chose is planar in the model 
    ## coordinate system
    set conExtents [$con getExtents]
    set chks1 [pwu::Vector3 subtract [lindex $conExtents 0] [lindex $conExtents 1]]
    set chks2 [pwu::Vector3 subtract $pt3 [lindex $conExtents 0]]
    
    ## If connector is planar and requires a 3D scale, compute random rotation
    ## angle (5-10 deg) to transform coordinate system prior to scale operation
    set rotationAngles [list]
    for {set ii 0} {$ii < 3} {incr ii} {
        if { [expr abs([lindex $chks1 $ii])] < 1e-4 && \
            [expr abs([lindex $chks2 $ii])] > 1e-4 } {
            lappend rotationAngles [expr 5+rand()*5.]
        } else {
            lappend rotationAngles 0.
        }
    }
    
    if {[pwu::Vector3 length $rotationAngles] > 0} {
        puts "Planar curve, implementing rotational transform..."
    }
    
    ## Set up paste command
    pw::Application clearClipboard
    pw::Application setClipboard [list $con]
    
    set pasteMode [pw::Application begin Paste]
        set modEnts [$pasteMode getEntities]
        set modMode [pw::Application begin Modify $modEnts]
            ## Translate connector
            pw::Entity transform [pwu::Transform translation $transVec] $modEnts
            ## Get the translated connector
            set newCon [lindex $modEnts 0]
            ## Get beginning point of new connector
            set pt4 [$newCon getPosition -arc 0]
            set pt2a [$newCon getPosition -arc 0.99]
            ## Make sure pt4 is set to the end of pasted connector opposite pt2
            if {[pwu::Vector3 equal -tolerance 1e-6 $pt2 $pt4]} {
                set pt4 [$newCon getPosition -arc 1]
                set pt2a [$newCon getPosition -arc 0.01]
            }

            set rightVec [pwu::Vector3 subtract $pt2a $pt2]
            set transformMatrix [pwu::Transform identity]

            set ii 0
            foreach ang $rotationAngles {
                set upVec {0 0 0}
                set upVec [lreplace $upVec $ii $ii 1]
                if {$ang != 0} {
                    set axis [pwu::Vector3 cross $rightVec $upVec]
                    set rotationMatrix [pwu::Transform rotation \
                        -anchor $pt2 $axis $ang]
                    set transformMatrix [pwu::Transform multiply \
                        $transformMatrix $rotationMatrix]
                }
                incr ii
            }
            
            pw::Entity transform $transformMatrix $newCon

            set inverseTransformMatrix [pwu::Transform inverse $transformMatrix]
            
            ## Transform points to handle 3D scaling of planar curves
            set pt3_t [pwu::Transform apply $transformMatrix $pt3]
            set pt4_t [pwu::Transform apply $transformMatrix $pt4]
            
            ## Scale pasted connector
            pw::Entity transform [pwu::Transform calculatedScaling $pt2 $pt4_t \
                $pt3_t [pw::Grid getNodeTolerance]] $newCon
            
            ## In some cases, you may want to stretch rather than scale
            #~ pw::Entity transform [pwu::Transform stretching $pt2 $pt4_t \
                #~ $pt3_t ] $newCon
                
            ## Transform back to model coordinate system
            pw::Entity transform $inverseTransformMatrix $newCon
        
        $modMode end
    $pasteMode end

    pw::Application clearClipboard
    
}

## Call each process
set con [selectCon]
squeezeCon $con

#############################################################################
#
# This file is licensed under the Cadence Public License Version 1.0 (the
# "License"), a copy of which is found in the included file named "LICENSE",
# and is distributed "AS IS." TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE
# LAW, CADENCE DISCLAIMS ALL WARRANTIES AND IN NO EVENT SHALL BE LIABLE TO
# ANY PARTY FOR ANY DAMAGES ARISING OUT OF OR RELATING TO USE OF THIS FILE.
# Please see the License for the full text of applicable terms.
#
#############################################################################
