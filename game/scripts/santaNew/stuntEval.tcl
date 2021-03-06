#----------------------------------------------------------------------
# constants
#----------------------------------------------------------------------

set ::onGround  0
set ::flight    1
set ::landing   2
set ::out       3
set ::nextStage 4

set ::flightThTime  0.4
set ::minLandThTime 0.2
set ::maxLandThTime 0.6
set ::jumpThTime    0.6
set ::outThTime     2.0

set ::flightTh  [expr $::flightThTime / $::seEvalPeriod]
set ::minLandTh [expr $::minLandThTime / $::seEvalPeriod] 
set ::maxLandTh [expr $::maxLandThTime / $::seEvalPeriod]
set ::outTh     [expr $::outThTime / $::seEvalPeriod]

set ::goalTh          5
set ::almostLandThAng 20

set ::cheerTh         0.9

set ::rot1Com [list $::soundDir/alright.wav \
		 $::soundDir/cool.wav]
set ::rot2Com [list $::soundDir/awesome.wav \
		  $::soundDir/yeeha.wav]
set ::rot2PlusCom [list $::soundDir/unbelievable.wav \
		      $::soundDir/noway.wav]

set ::rot1ComFrac 0.7
set ::rot2ComFrac 0.9
set ::rot2PlusComFrac 1.0

#----------------------------------------------------------------------
# state variables
#----------------------------------------------------------------------

set ::currTime 0
set ::currState {}
set ::currCol {}

set ::skierState $::onGround
set ::airCount 0
set ::landCount 0

set ::takeoffState {}      
set ::takeoffTime 0        
set ::landState {}         
set ::landTime 0
set ::crashState {}
set ::crashTime 0

set ::numTags 2
set ::numLinks 4
set ::f0 {}
set ::contact0 {}
set ::maxLandF {}
set ::crashLandF {}
set ::landContact {}          

set ::jumpInfo {}
set ::goalCount  0

set ::outCount 0

set ::noComment 0
set ::unconsciousOk 0

#----------------------------------------------------------------------
# functions
#----------------------------------------------------------------------

# initialize the states
proc seInit {} {
    reset
}

# evaluate stunt events
proc seEval { arg } {
    extractTime $arg
    extractState $arg
    extractCol $arg

    trans $arg
    sideEffects $arg
}

# extract the current time from the list of arguments
proc extractTime { arg } {
    set pos [lsearch $arg "t *"]
    set tRec [lindex $arg $pos]
    if {$tRec != ""} {
	set ::currTime [lindex $tRec 1]
    }
}

# extract the current state from the list of arguments
proc extractState { arg } {
    set pos [lsearch $arg "s *"]
    set sRec [lindex $arg $pos]
    if {$sRec != ""} {
	set ::currState $sRec
    }
}

# extract the collision info
proc extractCol { arg } {
    set pos [lsearch $arg "c *"]
    set cRec [lindex $arg $pos]
    if {$cRec != ""} {
	set ::currCol $cRec
    } else {
	set ::currCol {}
    }
}

# state transition
proc trans { arg } {
    if {$::skierState == $::nextStage} {
	return
    }

    if {$::skierState != $::out} {
	# check for unconscious skier
	set state $::currState
	if {$state != ""} {
	    if {[lindex $state 7] == 0} {
		startUnconscious
		return
	    }
	}
    }

    set gc [gndContact $arg]

    if {$::skierState == $::onGround} {
	if {$gc} {
	    set ::airCount 0
	} else {
	    if {$::airCount == 0} {
		# store takeoff state
		set ::takeoffState $::currState 
		set ::takeoffTime $::currTime
	    }

	    set ::airCount [expr $::airCount + 1]
	    if {$::airCount > $::flightTh} {
		startFlight
	    }
	}
    } elseif {$::skierState == $::flight} {
	if {$gc} {
	    if {$::landCount == 0} {
		set ::landState $::currState
		set ::landTime  $::currTime
	    } 
	    set ::landCount [expr $::landCount + 1]
	    if {$::landCount > $::minLandTh} {
		startLanding
	    }
	} else {
	    set ::landCount 0
	}
    } elseif {$::skierState == $::landing} {
	if {$gc} {
	    set ::landCount [expr $::landCount + 1]

	    if {$::landCount > $::maxLandTh} {
		startGround
	    }

	    set ::airCount 0
	} else {
	    if {$::airCount == 0} {
		# store takeoff state
		set ::takeoffState $::currState 
		set ::takeoffTime $::currTime
	    }

	    set ::airCount [expr $::airCount + 1]
	    if {$::airCount > $::flightTh} {
		startFlight
	    }
	}
    } elseif {$::skierState == $::out} {
	set ::outCount [expr $::outCount + 1]
    }
}

# determine if ground contact was detected
proc gndContact { arg } {
    set state $::currState
    if {$state != ""} {
	set numGndCnt [lindex $state 9]
	if [expr {$numGndCnt != ""} && {$numGndCnt > 0}] {
	    return 1
	}
    }

    return 0
}

# transition to flight state
proc _startFlight {} {
    set ::skierState $::flight
}

# transition to landing state
proc _startLanding {} {
    # determine jump info
    set jumpTime [expr $::landTime - $::takeoffTime]

    if [expr {$::jumpInfo == {}} && {$jumpTime > $::jumpThTime}] {
	set numRot [rotCount [lindex $::takeoffState 4] \
			[lindex $::landState 4]]
	set from [locMap map [lindex $::takeoffState 2] \
		      [lindex $::takeoffState 3]]
	set to [locMap map [lindex $::landState 2] \
		    [lindex $::landState 3]]
	set ::jumpInfo [list $jumpTime $numRot $from $to]
    } 

    set ::skierState $::landing
    set ::airCount 0
}

# transition to on-ground state
proc _startGround {} {
    # check the accumulated forces to see how smooth the landing was
    set os [onSkies $::currState]
    if {$os && $::jumpInfo != {}} {
	# ensure that a minimum number of ski points are in contact
	# with ground/active objects
	set bodyCount [lindex $::landContact 0]
	set skiCount  [lindex $::landContact 1]

	if {$skiCount > $bodyCount} {
	    if {$skiCount > 1} {
		processJump
	    } else {
		# it's unclear where the skier is grounded... so abort
		# the state transition and still consider this as landing
		return
	    }
	}
    }

    set ::skierState $::onGround
    set ::airCount 0
    set ::jumpInfo {}

    set ::maxLandF $::f0
    set ::landContact $::contact0
}

# transition to unconscious state
proc _startUnconscious {} {
    set ::crashState $::currState
    set ::crashTime $::currTime

    # clear forces so that we only accummulate the crash forces
    set ::crashLandF $::f0

    set ::skierState $::out
#    puts "unconscious at $::currTime"

    set skiesOn [lindex $::currState 8]

    if {$::unconsciousOk == 0} {
	message "Press <space> to retry" 20 20
    }
}

# transition to next-stage
proc _startNextStage {} {
    set ::skierState $::nextStage
}


# process a jump
proc _processJump {} {
    set numRot   [lindex $::jumpInfo 1]
    set from     [lindex $::jumpInfo 2]
    set to       [lindex $::jumpInfo 3]
    set absNumRot [abs $numRot]

    puts "from $from to $to"

    if {$absNumRot > 0} {
	if {[expr rand() < [expr $::cheerTh * $absNumRot]]} {
	    sound queue cheer $::soundDir/cheer3.wav
	}
    }

    if {$numRot == -1} {
	playCom $::soundDir/fflip.wav 0
    } elseif {$numRot == -2} {
	playCom $::soundDir/fflip2.wav 0
    } elseif {$numRot == 1} {
	playCom $::soundDir/bflip.wav 0
    } elseif {$numRot == 2} {
	playCom $::soundDir/bflip2.wav 0
    } else {
	puts "numRot = $numRot"
    }

    
    if {$absNumRot == 1} {
	set ci [expr int(rand() * [llength $::rot1Com])]
	set c [lindex $::rot1Com $ci]
	playComAtTimes $c $::rot1ComFrac
    } elseif {$absNumRot == 2} {
	set ci [expr int(rand() * [llength $::rot2Com])]
	set c [lindex $::rot2Com $ci]
	playComAtTimes $c $::rot2ComFrac
    } elseif {$absNumRot > 2} {
	set ci [expr int(rand() * [llength $::rot2PlusCom])]
	set c [lindex $::rot2PlusCom $ci]
	playComAtTimes $c $::rot2PlusComFrac
    }
}

# count the number of CCW rotations
proc rotCount { ang0 ang1 } {
    set nAng0 [normRndRot $ang0]
    set nAng1 [normRndRot $ang1]
    set rot   [expr $nAng1 - $nAng0]

    set rc   0
    set sign 1
    
    if {$rot < 0} {
	set sign -1
	set rot [expr $rot * -1]
    }

    while {$rot > 0} {
	if {$rot > 360} {
	    set rc [expr $rc + 1]
	    set rot [expr $rot - 360]
	} elseif {$rot > 180} {
	    set rc [expr $rc + 1]
	    break;
	} else {
	    break;
	}
    }

    return [expr $rc * $sign]
}

# normalize rotation to within -180 to 180 degrees
proc normRot { rot } {
    while {$rot > 180} {
	set rot [expr $rot - 360]
    }

    while {$rot < -180} {
	set rot [expr $rot + 360]
    }

    return $rot
}

# normalize and round the rotation to the closest 0 or 180 angle
proc normRndRot { rot } {
    set nRot [normRot $rot]
    set nrRot $rot
    if {[expr {$nRot >= 0} && {$nRot <= 90}]} {
	set nrRot [expr $rot - $nRot]
    } elseif {[expr {$nRot > 90} && {$nRot <= 180}]} {
	set nrRot [expr $rot - $nRot + 180.0]
    } elseif {[expr {$nRot > -180} && {$nRot <= -90}]} {
	set nrRot [expr $rot - $nRot - 180.0]
    } else {
	set nrRot [expr $rot - $nRot]
    }

    return $nrRot
}

# generate side effects
proc _sideEffects { arg } {
    if {$::skierState == $::nextStage} { return }

    if {$::skierState == $::onGround} {
    } elseif {$::skierState == $::flight} {
	set ::maxLandF [maxF $::maxLandF]
    } elseif {$::skierState == $::landing} {
	set ::maxLandF [maxF $::maxLandF]

	# accumulate contact points
	if {$::currCol != {}} {
	    set cl [lindex $::currCol 2]

	    for {set i 0} {$i < [llength $cl]} {set i [expr $i + 1]} {
		set c [lindex $cl $i]
		for {set j 0} {$j <$::numTags} {set j [expr $j + 1]} {
		    set cIndex [expr $j + 1]
		    set newC [lindex $c $cIndex]
		    if {$newC > [lindex $::landContact $j]} {
			set ::landContact \
			    [lreplace $::landContact $j $j $newC]
		    }
		}
	    }
	}
    } elseif {$::skierState == $::out} {
	if {$::outCount < $::outTh} {
	    set ::crashLandF [accumF $::crashLandF]
	}
    }

    crashEval::sideEffects $arg
}

# determine the maximum collision forces given the history of 
# the maximum forces detected so far
proc maxF { oldF } {
    # maximum forces
    if {$::currState != {}} {
	for {set i 0} {$i < [expr $::numLinks * 2]} {set i [expr $i + 1]} {
	    set fIndex [expr $i + 10]
	    set newF [abs [lindex $::currState $fIndex]]
	    if {$newF > [lindex $oldF $i]} {
		set oldF [lreplace $oldF $i $i $newF]
	    }
	}
    }

    return $oldF
}

# accummulate collision forces
proc accumF { oldF } {
    # accummulate forces
    if {$::currState != {}} {
	for {set i 0} {$i < [expr $::numLinks * 2]} {set i [expr $i + 1]} {
	    set fIndex [expr $i + 10]
	    set newF [abs [lindex $::currState $fIndex]]
	    set f [expr $newF + [lindex $oldF $i]]
	    set oldF [lreplace $oldF $i $i $f]
	}
    }

    return $oldF
}

# reset states
proc _reset {} {
    set ::currTime 0
    set ::currState {}
    set ::skierState $::onGround
    set ::airCount 0
    set ::landCount 0

    set ::takeoffState {}
    set ::takeoffTime 0
    set ::landState {}
    set ::landTime 0
    set ::crashState {}
    set ::crashTime 0

    set ::f0 {}
    for {set i 0} {$i < [expr 2 * $::numLinks]} {set i [expr $i + 1]} {
	lappend ::f0 0
    }
    set ::maxLandF $::f0
    set ::crashLandF $::f0

    set ::contact0 {}
    for {set i 0} {$i < $::numTags} {set i [expr $i + 1]} {
	lappend ::contact0 0
    }
    set ::landContact $::contact0

    set ::jumpInfo {}
    set ::goalCount 0
    set ::outCount 0

    set ::noComment 0

    crashEval::reset
}

# determine if the skier's on his skies
proc onSkies { state } {
    # examine the y component of the forces acting on all links
    # -> the skier is on his skies if the y component on the skies is
    #    greater than those from the other links
    
    set skiesFy [lindex $state 11]
    set thighFy [lindex $state 13]
    set torsoFy [lindex $state 15]
    set armFy   [lindex $state 17]

    if {$skiesFy < $thighFy} { 
	puts "thigh collision"
	return 0 
    }
    if {$skiesFy < $torsoFy} { 
	puts "torso collision"
	return 0 
    }
    if {$skiesFy < $armFy} { 
	puts "arm collision"
	return 0 
    }

    return 1
} 

# use the info accummulated during landing to determine whether
# the skier's standing on his skies
proc landOnSkies {} {
    # ensure that a minimum number of ski points are in contact
    # with ground/active objects
    set bodyCount [lindex $::landContact 0]
    set skiCount  [lindex $::landContact 1]
    
    if [expr {$skiCount > $bodyCount} && {$skiCount > 1}] {
	return 1
    } else {
	puts "bodyCount = $bodyCount"
	puts "skiCount = $skiCount"
	return 0
    }

    return 1;

}

# helper routine that verifies that the goal is reached IFF the
# goal condition is met ::goalTh number of times in a row
proc goal { goalMet } {
    if {$goalMet == 1} {
	if {$::goalCount > $::goalTh} {
	    goalReached
	} else {
	    set ::goalCount [expr $::goalCount + 1]
	}
    } else {
	set ::goalCount 0
    }
}

# absolute value
proc abs { n } {
    if { $n < 0 } {
	return [expr $n * -1]
    }
    return $n
}

# play comment
proc playCom { fname force } {
    if {[expr {$::noComment == 0} || {$force}]} {
	sound queue comment $fname
    } 
}

# play comment with "frac" probability
proc playComAtTimes { fname frac } {
    if {$::noComment == 0} {
	if {[expr rand()] < $frac} {
	    sound queue comment $fname
	    return 1
	}
    } 
    return 0
}

# determine if the skier almost landed:
# - if the ski angle is close to the ground angle
proc almostLand { gndAng } {
    set ang [expr [normRot [lindex $::currState 4]] - $gndAng]
    set absAng [abs $ang]

    return [expr $absAng < $::almostLandThAng]
}

# return the name binded to the location where the skier is
proc currLoc {} {
    return [locMap map [lindex $::currState 2] \
		[lindex $::currState 3]]
}

# accummulate collisions to the specific type of object for
# specific body parts
proc accumCol { colType colIndex origCol } {
    # check for tree collisions
    if {$::currCol != {}} {
	set cl [lindex $::currCol 2]
	for {set i 0} {$i < [llength $cl]} {set i [expr $i + 1]} {
	    set c [lindex $cl $i]
	    set type [lindex $c 0]
	    if {$type == $colType} {
		if {$colIndex == 0} {
		    return [expr $origCol + 1]
		} elseif {[lindex $c $colIndex] > 0} {
		    return [expr $origCol + 1]
		}
	    }
	}
    }

    return $origCol
}

#----------------------------------------------------------------------
# helper modules
#----------------------------------------------------------------------

source ski/crashEval.tcl
source ski/landEval.tcl

#----------------------------------------------------------------------
# overridable routines
#----------------------------------------------------------------------

proc startFlight {} {
    _startFlight
}

proc startLanding {} {
    _startLanding
}

proc startGround {} {
    _startGround
}

proc startUnconscious {} {
    _startUnconscious
}

proc sideEffects { arg } {
    _sideEffects arg
}

proc processJump {} {
    _processJump
}

proc startNextStage {} {
    _startNextStage
}

proc reset {} {
    _reset
}

proc showGoal {} {
    # to be overridden
}

proc goalReached {} {
    # to be overridden
}

set ::nextStageName ""

proc keySpace {} {
    changeStage
}

proc keyg {} {
    showGoal
}

proc changeStage {} {
    _changeStage 
}

proc _changeStage {} {
    if {[expr {$::skierState == $::nextStage} && {$::nextStageName != ""}]} {
	startNewStage ski/$::nextStageName/setup
    } else {
	keyr
    }
}
