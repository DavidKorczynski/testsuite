#!/bin/bash

#for user doc, check scripts/00-template

base_args=""

GNU_TIME=/usr/bin/time
GNU_DATE=date
GNU_TIMEOUT=timeout
#GNU_SED=sed
DIFF=diff
GCOV=gcov
FFMPEG=ffmpeg
READLINK=readlink

EXTERNAL_MEDIA_AVAILABLE=1

platform=`uname -s`


if [ $platform = "Darwin" ] ; then
GNU_TIME=gtime
GNU_DATE=gdate
GNU_TIMEOUT=gtimeout
READLINK=greadlink
fi


#if the script in launched from elsewhere, main_dir still needs to be the script directory
main_dir="$(dirname $($READLINK -f $0))"
cd $main_dir

#if launched from an absolute path, set all paths as absolute (will break on cygwin)
rel_main_dir="."
if [[ "$0" = /* ]]; then
  rel_main_dir=$main_dir
fi


MP4CLIENT_NOT_FOUND=0

generate_hash=0
play_all=0
global_test_ui=0
log_after_fail=0
verbose=0
enable_timeout=0
enable_fuzzing=0
fuzz_all=0
fuzz_duration=60
no_fuzz_cleanup=0

current_script=""

DEF_DUMP_DUR=10
DEF_DUMP_SIZE="200x200"
DEF_TIMEOUT=20

#remote location of resource files: all media files, hash files and generated videos
REFERENCE_DIR="http://download.tsi.telecom-paristech.fr/gpac/gpac_test_suite/resources"
#dir where all external media are stored
EXTERNAL_MEDIA_DIR="$rel_main_dir/external_media"
#dir where all hashes are stored
HASH_DIR="$rel_main_dir/hash_refs"
#dir where all specific test rules (override of defaults, positive tests, ...) are stored
RULES_DIR="$rel_main_dir/rules"
#dir where all referenced videos are stored
SCRIPTS_DIR="$rel_main_dir/scripts"
#dir where all referenced videos are stored
VIDEO_DIR_REF="$rel_main_dir/external_videos_refs"

#dir where all local media data (ie from git repo) is stored
MEDIA_DIR="$rel_main_dir/media"
#local dir where all data will be generated (except hashes and referenced videos)
LOCAL_OUT_DIR="$rel_main_dir/results"

#dir where all test videos are generated
VIDEO_DIR="$LOCAL_OUT_DIR/videos"
#dir where all logs are generated
LOGS_DIR="$LOCAL_OUT_DIR/logs"
#temp dir for any test
TEMP_DIR="$LOCAL_OUT_DIR/temp"

ALL_REPORTS="$LOCAL_OUT_DIR/all_results.xml"
ALL_LOGS="$LOCAL_OUT_DIR/all_logs.txt"

TEST_ERR_FILE="$TEMP_DIR/err_exit"

rm -f "$TEST_ERR_FILE" 2> /dev/null
rm -f "$LOGS_DIR/*.sh" 2> /dev/null

if [ ! -e $LOCAL_OUT_DIR ] ; then
mkdir $LOCAL_OUT_DIR
fi

if [ ! -e $HASH_DIR ] ; then
mkdir $HASH_DIR
fi

if [ ! -e $VIDEO_DIR ] ; then
mkdir $VIDEO_DIR
fi

if [ ! -e $VIDEO_DIR_REF ] ; then
mkdir $VIDEO_DIR_REF
fi


if [ ! -e $LOGS_DIR ] ; then
mkdir $LOGS_DIR
fi

if [ ! -e $RULES_DIR ] ; then
mkdir $RULES_DIR
fi

if [ ! -e $TEMP_DIR ] ; then
mkdir $TEMP_DIR
fi

L_ERR=1
L_WAR=2
L_INF=3
L_DEB=4

log()
{
 if [ $TERM = "cygwin" ]; then

  if [ $1 = $L_ERR ]; then
    echo -ne "\033[31m"
  elif [ $1 = $L_WAR ]; then
    echo -ne "\033[32m"
  elif [ $1 = $L_INF ]; then
    echo -ne "\033[34m"
  elif [ $verbose = 0 ]; then
    echo -ne "\033[0m"
    return
  fi

  echo $2
  echo -ne "\033[0m"

 else

  if [ $1 = $L_ERR ]; then
    tput setaf 1
  elif [ $1 = $L_WAR ]; then
    tput setaf 2
  elif [ $1 = $L_INF ]; then
    tput setaf 4
  elif [ $verbose = 0 ]; then
    tput sgr0
    return
  fi

  echo $2
  tput sgr0

 fi
}

print_usage ()
{
echo "GPAC Test Suite Usage: use either one of this command or no command at all"
echo "*** Test suite validation options"
echo "  -clean [ARG]:          removes all removes all results (logs, stat cache and video). If ARG is specified, only clean tests generated by script ARG."
echo "  -play-all:             force playback of BT and XMT files for BIFS (by default only MP4)."
echo "  -no-hash:              runs test suite without hash checking."
echo ""
echo "*** Test suite generation options"
echo "  -clean-hash [ARG]:     removes all generated hash, logs, stat cache and videos. If ARG is specified, only clean tests generated by script ARG."
echo "  -hash:                 regenerate tests with missing hash files."
echo "  -uirec:                generates UI event traces."
echo "  -uiplay:               replays all recorded UI event traces."
echo "  -speed=N:              sets playback speed for -uiplay. Default is 1."
echo ""
echo "*** Fuzzing options"
echo "  -do-fuzz:              runs test using afl-fuzz (gpac has to be compiled with afl-gcc first)."
echo "  -fuzzdur=D:            runs fuzz tests for D (default is $fuzz_duration seconds). D is passed as is to timout program."
echo "  -fuzzall:              fuzz all tests."
echo "  -keepfuzz:             keeps all fuzzing data."
echo ""
echo "*** General options"
echo "  -strict:               stops at the first failed test"
echo "  -warn:                 dump logs after each failed test (used for travisCI)"
echo "  -keep-avi:             keeps raw AVI files (warning this can be pretty big)"
echo "  -keep-tmp:             keeps tmp folder used in tests (erased by default)"
echo "  -sync-hash:            syncs all remote reference hashes with local base"
echo "  -sync-media:           syncs all remote media with local base (warning this can be long)"
echo "  -sync-refs:            syncs all remote reference videos with local base (warning this can be long)"
echo "  -sync-before:          syncs all remote resources with local base (warning this can be long) before running the tests"
echo "  -check:                check test suites (names of each test is unique)"
echo "  -track-stack:          track stack in malloc and turns on -warn option"
echo "  -noplay:               disables MP4Client tests"
echo "  -test=NAME             only executes given test"
echo "  -v:                    set verbose output"
echo "  -h:                    print this help"
}


#performs mirroring of media and references hash & videos
sync_media ()
{
 log $L_INF "- Mirroring $REFERENCE_DIR/media/ to $EXTERNAL_MEDIA_DIR"
 if [ ! -e $EXTERNAL_MEDIA_DIR ] ; then
  mkdir $EXTERNAL_MEDIA_DIR
 fi
 cd $EXTERNAL_MEDIA_DIR
 wget -q -m -nH --no-parent --cut-dirs=4 --reject "*.gif" "$REFERENCE_DIR/media/"
 cd "$main_dir"
}

#performs mirroring of media
sync_hash ()
{
log $L_INF "- Mirroring reference hashes from from $REFERENCE_DIR to $HASH_DIR"
cd $HASH_DIR
wget -q -m -nH --no-parent --cut-dirs=4 --reject "*.gif" "$REFERENCE_DIR/hash_refs/"
cd "$main_dir"
}

#performs mirroring of media and references hash & videos
sync_refs ()
{
log $L_INF "- Mirroring reference videos from $REFERENCE_DIR to $VIDEO_DIR_REF"
cd $VIDEO_DIR_REF
wget -q -m -nH --no-parent --cut-dirs=4 --reject "*.gif" "$REFERENCE_DIR/video_refs/"
cd "$main_dir"
}


url_arg=""
do_clean=0
keep_avi=0
do_clean_hash=0
check_only=0
disable_hash=0
strict_mode=0
track_stack=0
speed=1
single_test_name=""
erase_temp_dir=1

#Parse arguments
for i in $* ; do
 case $i in
 "-hash")
  generate_hash=1;;
 "-play-all")
   play_all=1;;
 "-clean")
   do_clean=1;;
 "-clean-hash")
   do_clean_hash=1;;
 "-uirec")
  global_test_ui=1;;
 "-uiplay")
  global_test_ui=2;;
 -speed*)
  speed="${i#-speed=}"
  ;;
 "-keep-avi")
  keep_avi=1;;
 "-keep-tmp")
  erase_temp_dir=0;;
 "-no-hash")
  disable_hash=1;;
 "-strict")
  strict_mode=1;;
 "-do-fuzz")
  enable_fuzzing=1;;
 -fuzzdur*)
  fuzz_duration="${i#-fuzzdur=}"
  ;;
 "-fuzzall")
  fuzz_all=1;;
 "-keepfuzz")
  no_fuzz_cleanup=1;;
 "-sync-hash")
  sync_hash
  exit;;
 "-sync-media")
  sync_media;;
 "-sync-refs")
  sync_refs
  exit;;
 "-sync-before")
  sync_media;;
 "-check")
  check_only=1;;
 "-warn")
  log_after_fail=1;;
 "-track-stack")
  track_stack=1;;
 "-noplay")
	MP4CLIENT_NOT_FOUND=1;;
 -test*)
  single_test_name="${i#-test=}"
  ;;
 "-v")
  verbose=1;;
 "-h")
  print_usage
  exit;;
 -*)
   log $L_ERR "Unknown Option \"$i\" - check usage (-h)"
   exit;;
 *)
  if [ -n "$url_arg" ] ; then
   log $L_ERR "More than one input specified - check usage (-h)"
   exit
  else
   url_arg=$i
  fi
 ;;
esac
done

if [ $check_only != 0 ] ; then
 do_clean_hash=0
 do_clean=0
 global_test_ui=0
fi

#Clean all hashes and reference videos
if [ $do_clean_hash != 0 ] ; then

 #force cleaning as well
 do_clean=1

 if [ -n "$url_arg" ] ; then
  do_clean=1
 else
  read -p "This will remove all referenced videos and hashes. Are you sure (y/n)?" choice
  if [ $choice != "y" ] ; then
   log $L_ERR "Canceled"
   exit
  fi
  log $L_INF "Deleting SHA-1 Hashes"
  rm -rf $HASH_DIR/* 2> /dev/null
  rm -rf $VIDEO_DIR_REF/* 2> /dev/null
 fi
fi

#Clean all cached results and generated videos
if [ $do_clean != 0 ] ; then
 rm -f $ALL_REPORTS > /dev/null
 rm -f $ALL_LOGS > /dev/null
 rm -rf $TEMP_DIR/* 2> /dev/null
 if [ -n "$url_arg" ] ; then
  do_clean=1
 else
  echo "Deleting cache (logs, stats and videos)"
  rm -rf $LOGS_DIR/* > /dev/null
  rm -rf $VIDEO_DIR/* 2> /dev/null
  exit
 fi
fi

log $L_INF "Checking test suite config"

if [ $generate_hash = 0 ] ; then
 if [ ! "$(ls -A $HASH_DIR)" ]; then
  disable_hash=1
  log $L_WAR "- Reference hashes unavailable - you may sync them using -sync-hash  - skipping hash tests"
  else
  log $L_INF "- Reference hashes available - enabling hash tests"
 fi
fi

if [ ! -e $EXTERNAL_MEDIA_DIR ] ; then
EXTERNAL_MEDIA_AVAILABLE=0
elif [ ! -e $EXTERNAL_MEDIA_DIR/counter ] ; then
EXTERNAL_MEDIA_AVAILABLE=0
fi

if [ $EXTERNAL_MEDIA_AVAILABLE = 0 ] ; then
 log $L_WAR "- External media dir unavailable - you may sync it using -sync-media"
else
 log $L_INF "- External media dir available"
fi

#test for GNU time
$GNU_TIME ls > /dev/null 2>&1
res=$?
if [ $res != 0 ] ; then
log $L_ERR "GNU time not found (ret $res) - exiting"
exit 1
fi

#test for GNU date
$GNU_DATE > /dev/null 2>&1
res=$?
if [ $res != 0 ] ; then
log $L_ERR "GNU date not found (ret $res) - exiting"
exit 1
fi

#test for timeout
$GNU_TIMEOUT 1.0 ls > /dev/null 2>&1
res=$?
if [ $res != 0 ] ; then
 log $L_ERR "GNU timeout not found (ret $res) - some tests may hang forever ..."
 enable_timeout=0
 if [ $enable_fuzzing != 0 ] ; then
  log $L_ERR "GNU timeout not found - disabling fuzzing"
  enable_fuzzing=0
 fi
else
enable_timeout=1
fi


#test for ffmpeg - if not present, disable video storing
do_store_video=1

if [ $check_only = 0 ] ; then


$FFMPEG -version > /dev/null 2>&1
if [ $? != 0 ] ; then
log $L_WAR "- FFMPEG not found - disabling playback video storage"
do_store_video=0
else
  if [ $generate_hash != 0 ] ; then
	log $L_INF "- Generating reference videos"
  fi
fi


#check MP4Box, gpac, MP4Client and MP42TS (use default args, not custum ones because of -mem-track)
MP4Box -h 2> /dev/null
res=$?
if [ $res != 0 ] ; then
log $L_ERR "MP4Box not found (ret $res) - exiting"
exit 1
fi


gpac -h 2> /dev/null
res=$?
if [ $res != 0 ] ; then
log $L_ERR "gpac not found (ret $res) - exiting"
exit 1
fi


MP4CLIENT="MP4Client"

if [ $MP4CLIENT_NOT_FOUND = 0 ] && [ $do_clean = 0 ] ; then
  MP4Client -run-for 0 2> /dev/null
  res=$?
  if [ $res != 0 ] ; then
    MP4CLIENT_NOT_FOUND=1
    echo ""
    log $L_WAR "WARNING: MP4Client not found (ret $res) - launch results:"
    MP4Client -run-for 0
    res=$?
    if [ $res = 0 ] ; then
      log $L_INF "MP4Client returned $res on second run - enabling all playback tests"
    else
      echo "** MP4Client returned $res - disabling all playback tests - dumping GPAC config file **"
      cat $HOME/.gpac/GPAC.cfg
      echo "** End of dump **"
    fi
  fi
fi

MP42TS -h 2> /dev/null
res=$?
if [ $res != 0 ] ; then
log $L_ERR "MP42TS not found (ret $res) - exiting"
exit 1
fi

#check mem tracking is supported
res=`MP4Box -mem-track -h 2>&1 | grep "WARNING"`
if [ -n "$res" ]; then
  log $L_WAR "- GPAC not compiled with memory tracking"
else
 log $L_INF "- Enabling memory-tracking"
 if [ $track_stack = 1 ]; then
  base_args="$base_args -mem-track-stack"
  log_after_fail=1
 else
  base_args="$base_args -mem-track"
 fi
fi

#end check_only
fi

#check for afl-fuzz
if [ $enable_fuzzing != 0 ] ; then
 log $L_INF "Checking for afl-fuzz"
 command -v afl-fuzz >/dev/null 2>&1
 if [ $? != 0 ] ; then
  log $L_WAR "afl-fuzz not found - disabling fuzzing"
  enable_fuzzing=0
 else
  mkdir tmpafi
  mkdir tmpafo

  echo "void" > tmpafi/void.mp4
  $GNU_TIMEOUT 3.0 afl-fuzz -d -i tmpafi -o tmpafo MP4Box -h > /dev/null
  if [ $? != 0 ] ; then
   log $L_WAR "afl-fuzz not properly configure:"
   afl-fuzz -d -i tmpafi -o tmpafo MP4Box -h
   exit
  else
   log $L_INF "afl-fuzz found and OK - enabling fuzzing with duration $fuzz_duration"
  fi
  rm -rf tmpaf*
 fi
fi

echo ""

#reassign our default programs
MP4BOX="MP4Box -noprog -for-test $base_args"
GPAC="gpac $base_args"
MP4CLIENT="MP4Client -noprog -strict-error $base_args"
MP42TS="MP42TS $base_args"
DASHCAST="DashCast $base_args"

$MP4BOX -version 2> $TEMP_DIR/version.txt
VERSION="`head -1 $TEMP_DIR/version.txt | cut -d ' ' -f 5-` "
rm $TEMP_DIR/version.txt

#reset all the possible return values
reset_stat ()
{
 EXECUTION_STATUS="N/A"
 RETURN_VALUE="N/A"
 MEM_TOTAL_AVG="N/A"
 MEM_RESIDENT_AVG="N/A"
 MEM_RESIDENT_MAX="N/A"
 CPU_PERCENT="N/A"
 CPU_ELAPSED_TIME="N/A"
 CPU_USER_TIME="N/A"
 CPU_KERNEL_TIME="N/A"
 PAGE_FAULTS="N/A"
 FILE_INPUTS="N/A"
 SOCKET_MSG_REC="N/A"
 SOCKET_MSG_SENT="N/A"
}

#begin a test with name $1 and using hashes called $1-$2 ... $1-$N
test_begin ()
{
  if [ $# -gt 1 ] ; then
   log $L_ERR "> in script $current_script line $BASH_LINENO"
   log $L_ERR "	@test_begin takes only two arguments - wrong call (first arg is $1)"
  fi

 test_skip=0
 result=""
 TEST_NAME=$1
 fuzz_test=$fuzz_all
 reference_hash_valid="$HASH_DIR/$TEST_NAME-valid-hash"

 log $L_DEB "Starting test $TEST_NAME"


 if [ $do_clean != 0 ] ; then
  if [ $do_clean_hash != 0 ] ; then
   rm -rf $HASH_DIR/$TEST_NAME* 2> /dev/null
   rm -rf $VIDEO_DIR_REF/$TEST_NAME* 2> /dev/null
   rm -rf $reference_hash_valid 2> /dev/null
  fi
  rm -rf $LOGS_DIR/$TEST_NAME* > /dev/null
  rm -rf $VIDEO_DIR/$TEST_NAME* 2> /dev/null
  test_skip=1
  return
 fi

 if [ $check_only != 0 ] ; then
  test_ui=0
  report="$TEMP_DIR/$TEST_NAME.test"
  if [ -f $report ] ; then
   log $L_ERR "Test $TEST_NAME already exists - please fix ($current_script)"
   rm -rf $TEMP_DIR/* 2> /dev/null
   exit
  fi
  echo "" > $report
  test_skip=1
  return
 fi

 report="$TEMP_DIR/$TEST_NAME-temp.txt"
 LOGS="$LOGS_DIR/$TEST_NAME-logs.txt-new"
 final_report="$LOGS_DIR/$TEST_NAME-passed.xml"

 #reset defaults
 dump_dur=$DEF_DUMP_DUR
 dump_size=$DEF_DUMP_SIZE
 test_timeout=$DEF_TIMEOUT

 test_skip=0
 single_test=0

 test_args="$@"
 test_nb_args=$#
 skip_play_hash=0
 subtest_idx=0
 nb_subtests=0
 test_ui=$global_test_ui

 test_stats="$LOGS_DIR/$TEST_NAME-stats.sh"

 #if error in strict mode, mark the test as skippable using value 2
 if [ $strict_mode = 1 ] ; then
  if [ -f $TEST_ERR_FILE ] ; then
   test_skip=2
  fi
 fi

 if [ $MP4CLIENT_NOT_FOUND > 0 ] ; then
  skip_play_hash=1
 fi

 if [ $generate_hash = 1 ] ; then
  #skip test only if reference hash is marked as valid
  if [ -f "$reference_hash_valid" ] ; then
   log $L_DEB "Reference hash found for test $TEST_NAME - skipping hash generation"
   test_skip=1
  fi
 elif [ $test_ui != 0 ] ; then
   test_skip=0
 elif [ $test_skip = 0 ] ; then
  #skip test only if final report is present (whether we generate hashes or not)
  if [ -f "$final_report" ] ; then
   if [ -f "$test_stats" ] ; then
    log $L_DEB "$TEST_NAME already passed - skipping"
    test_skip=1
   else
    log $L_WAR "$TEST_NAME already passed but missing stats.sh - regenerating"
   fi
  fi
 fi

 if [ "$single_test_name" != "" ] && [ "$single_test_name" != "$TEST_NAME" ] ; then
   test_ui=0
   test_skip=1
 fi

 if [ $test_skip != 0 ] ; then
   #stats.sh may be missing when generating hashes and that's not an error
   if [ -f "$test_stats" ] ; then
    has_skip=`grep -w "TEST_SKIP" $test_stats`

    if [ "$has_skip" = "" ]; then
		echo "TEST_SKIP=$test_skip" >> $test_stats
    fi
   fi
   test_skip=1
 elif [ $test_ui != 0 ] ; then
   #in UI test mode don't check cache status, always run the tests
   test_skip=1
 else
  echo "*** $TEST_NAME logs (GPAC version $VERSION) - test date $(date '+%d/%m/%Y %H:%M:%S') ***" > $LOGS
  echo "" >> $LOGS
 fi


 rules_sh=$RULES_DIR/$TEST_NAME.sh
 if [ -f $rules_sh ] ; then
  source $rules_sh
 fi

}

mark_test_error ()
{
 if [ $strict_mode = 1 ] ; then
  echo "" > $TEST_ERR_FILE
  log $L_ERR "Error test $TEST_NAME subtest $SUBTEST_NAME - aborting"
 fi
}


#ends test - gather all logs/stats produced and generate report
test_end ()
{
 #wait for all sub-tests to complete (some may use subshells)
 wait

  if [ $# -gt 0 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@test_end takes no argument - wrong call"
  fi

 if [ $test_skip = 1 ] ; then
  return
 fi

 test_stats="$LOGS_DIR/$TEST_NAME-stats.sh"
 echo "" > $test_stats
 stat_xml_temp="$TEMP_DIR/$TEST_NAME-statstemp.xml"
 echo "" > $stat_xml_temp

 test_fail=0
 test_leak=0
 test_exec_na=0
 nb_subtests=0
 nb_test_hash=0
 nb_hash_fail=0
 nb_hash_missing=0

 if [ "$result" != "" ] ; then
  test_fail=1
 fi

# makes glob on non existing files to expand to null
# enabling loops on nonexisting* to be empty
shopt -s nullglob

 #gather all stats per subtests
 for i in $TEMP_DIR/$TEST_NAME-stats-*.sh ; do
  reset_stat
  RETURN_VALUE=0
  SUBTEST_NAME=""
  COMMAND_LINE=""
  SUBTEST_IDX=0

  nb_subtests=$((nb_subtests + 1))

  source $i

  echo "  <stat subtest=\"$SUBTEST_NAME\" execution_status=\"$EXECUTION_STATUS\" return_status=\"$RETURN_STATUS\" mem_total_avg=\"$MEM_TOTAL_AVG\" mem_resident_avg=\"$MEM_RESIDENT_AVG\" mem_resident_max=\"$MEM_RESIDENT_MAX\" cpu_percent=\"$CPU_PERCENT\" cpu_elapsed_time=\"$CPU_ELAPSED_TIME\" cpu_user_time=\"$CPU_USER_TIME\" cpu_kernel_time=\"$CPU_KERNEL_TIME\" page_faults=\"$PAGE_FAULTS\" file_inputs=\"$FILE_INPUTS\" socket_msg_rec=\"$SOCKET_MSG_REC\" socket_msg_sent=\"$SOCKET_MSG_SENT\" return_value=\"$RETURN_VALUE\">" >> $stat_xml_temp

  echo "   <command_line>$COMMAND_LINE</command_line>" >> $stat_xml_temp
  echo "  </stat>" >> $stat_xml_temp

  test_ok=1

  if [ $RETURN_VALUE -eq 1 ] ; then
   result="$SUBTEST_NAME:Fail $result"
   test_ok=0
   test_fail=$((test_fail + 1))
  elif [ $RETURN_VALUE -eq 2 ] ; then
   result="$SUBTEST_NAME:MemLeak $result"
   test_ok=0
   test_leak=$((test_leak + 1))
  elif [ $RETURN_VALUE != 0 ] ; then
   if [ $enable_timeout != 0 ] && [ $RETURN_VALUE = 124 ] ; then
    result="$SUBTEST_NAME:Timeout $result"
   else
    result="$SUBTEST_NAME:Fail(ret code $RETURN_VALUE) $result"
   fi
   test_ok=0
   test_fail=$((test_fail + 1))
  fi

  if [ $log_after_fail = 1 ] ; then
   if [ $test_ok = 0 ] ; then
    sublog=$LOGS_DIR/$TEST_NAME-logs-$SUBTEST_IDX-$SUBTEST_NAME.txt
    if [ -f $sublog ] ; then
	 cat $sublog 2> stderr
    fi
   fi
  fi
  rm -f $i > /dev/null
 done

 #gather all hashes for this test
 for i in $TEMP_DIR/$TEST_NAME-stathash-*.sh ; do
  if [ -f $i ] ; then
   HASH_TEST=""
   HASH_NOT_FOUND=0
   HASH_FAIL=0

   source $i
   nb_test_hash=$((nb_test_hash + 1))
   if [ $HASH_NOT_FOUND -eq 1 ] ; then
    result="$HASH_TEST:HashNotFound $result"
    nb_hash_missing=$((nb_hash_missing + 1))
    test_exec_na=$((test_exec_na + 1))
   elif [ $HASH_FAIL -eq 1 ] ; then
    result="$HASH_TEST:HashFail $result"
    test_ok=0
    nb_hash_fail=$((nb_hash_fail + 1))
    test_exec_na=$((test_exec_na + 1))
   fi
  fi
  rm -f $i > /dev/null
 done

 if [ "$result" = "" ] ; then
  result="OK"
 fi

 if [ ! -f $TEST_ERR_FILE ] ; then
  if [ $generate_hash = 1 ] ; then
    log $L_DEB "Test $TEST_NAME $nb_subtests subtests and $nb_test_hash hashes"
    nb_hashes=$((nb_test_hash + nb_test_hash))
	#only allow no hash if only one subtest
    if [ $subtest_idx -gt 1 ] && [ $nb_hashes -lt $subtest_idx ] ; then
     log $L_ERR "Test $TEST_NAME has too few hash tests: $nb_hashes for $nb_subtests subtests - please fix"
     result="NOT ENOUGH HASHES"
    else
		echo "ok" > $reference_hash_valid
	fi
#    if [ $nb_test_hash -gt 15 ] ; then
#     log $L_WAR "Test $TEST_NAME has too many subtests with hashes ($nb_test_hash), not efficient for hash generation - consider rewriting $current_script"
#	fi
  fi
 fi


 echo " <test name=\"$TEST_NAME\" result=\"$result\" date=\"$(date '+%d/%m/%Y %H:%M:%S')\">" > $report
 cat $stat_xml_temp >> $report
 rm -f $stat_xml_temp > /dev/null
 echo " </test>" >> $report

 echo "TEST_FAIL=$test_fail" >> $test_stats
 echo "TEST_EXEC_NA=$test_exec_na" >> $test_stats
 echo "SUBTESTS_LEAK=$test_leak" >> $test_stats
 echo "NB_HASH_SUBTESTS=$nb_test_hash" >> $test_stats
 echo "NB_HASH_SUBTESTS_MISSING=$nb_hash_missing" >> $test_stats
 echo "NB_HASH_SUBTESTS_FAIL=$nb_hash_fail" >> $test_stats

 # list all logs files
 for i in $LOGS_DIR/$TEST_NAME-logs-*.txt; do
  cat $i >> $LOGS
 done
 rm -f $LOGS_DIR/$TEST_NAME-logs-*.txt > /dev/null

 echo "NB_SUBTESTS=$nb_subtests" >> $test_stats

 if [ "$result" == "OK" ] ; then
  mv $report "$LOGS_DIR/$TEST_NAME-passed-new.xml"

  echo "$TEST_NAME: $result"
 else
  mv $report "$LOGS_DIR/$TEST_NAME-failed.xml"
  mark_test_error

  log $L_ERR "$TEST_NAME: $result"
 fi

}

do_fuzz()
{
  cmd="$2"
  fuzz="@@"
  fuzz_cmd=${cmd/$1/$fuzz}
  file_ext="${1##*.}"
  orig_path=`pwd`
  tests_gen=0
  log $L_DEB "Fuzzing file $1 with command line $fuzz_cmd"

  fuzz_res_dir="$LOCAL_OUT_DIR/fuzzing/$TEST_NAME_$SUBTEST_NAME/$fuzz_sub_idx"
  fuzz_temp_dir="$LOCAL_OUT_DIR/fuzzing/$TEST_NAME_$SUBTEST_NAME/$fuzz_sub_idx/temp"
  mkdir -p "$fuzz_res_dir"
  mkdir -p "$fuzz_temp_dir/in/"
  mkdir -p "$fuzz_temp_dir/out/"

  cp $1 "$fuzz_temp_dir/in/"
  cd $fuzz_temp_dir

  $GNU_TIMEOUT $fuzz_duration afl-fuzz -d -i "in/" -o "out/" $fuzz_cmd
  if [ $? = 0 ] ; then
   if [ $no_fuzz_cleanup = 0 ] ; then
    #rename all crashes and hangs
    cd out/crashes
    ls | cat -n | while read n f; do mv "$f" "$fuzz_res_dir/crash_$n.$file_ext"; done
    cd ../hangs
    ls | cat -n | while read n f; do mv "$f" "$fuzz_res_dir/hang_$n.$file_ext"; done
    cd ../..
    rm -f "$fuzz_res_dir/readme.txt"
   fi
  fi

  cd "$orig_path"

  if [ $no_fuzz_cleanup = 0 ] ; then
   rm -rf $fuzz_temp_dir

   tests_gen=`ls $fuzz_res_dir | wc -w`
   if [ $no_fuzz_cleanup != 0 ] ; then
    tests_gen=1
   fi

   if [ $tests_gen = 0 ] ; then
    rm -rf $fuzz_res_dir
   else
    echo "Generated with afl-fuzz -d $fuzz_cmd" > "$fuzz_res_dir/readme.txt"
   fi
  fi
}

#@do_test execute the command line given $1 using GNU time and store stats with return value, command line ($1) and subtest name ($2)
ret=0
do_test ()
{

  if [ $# -gt 2 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@do_test takes only two arguments - wrong call (first arg $1)"
  fi

 if [ $strict_mode = 1 ] ; then
  if [ -f $TEST_ERR_FILE ] ; then
   return
  fi
 fi

 if [ $test_skip = 1 ] ; then
  return
 fi

 if [ $MP4CLIENT_NOT_FOUND != 0 ] ; then
	case $1 in MP4Client*)
		return
	esac
 fi
 log L_DEB "executing $1"

 subtest_idx=$((subtest_idx + 1))

 log_subtest="$LOGS_DIR/$TEST_NAME-logs-$subtest_idx-$2.txt"
 stat_subtest="$TEMP_DIR/$TEST_NAME-stats-$subtest_idx-$2.sh"
 SUBTEST_NAME=$2

 if [ $enable_fuzzing = 0 ] ; then
  fuzz_test=0
 fi

 #fuzzing on: check all args, detect ones matching input files in $maindir and fuzz them
 #note that this is not perfect since the command line may modify an existing MP4
 #so each successfull afl-fuzz test (not call!) will modify the input...
 if [ $fuzz_test != 0 ] ; then
  fuzz_dir="$LOCAL_OUT_DIR/fuzzing/$TEST_NAME_$SUBTEST_NAME/"
  mkdir -p fuzz_dir
  fuzz_sub_idx=1
  for word in $1 ; do
   is_file_arg=0
   case "$word" in
     $main_dir/*)
      is_file_arg=1;;
   esac

   if [ $is_file_arg != 0 ] ; then
    fuzz_src=${word%:*}
    if [ -f $fuzz_src ] ; then
      do_fuzz "$fuzz_src" "$1"
      fuzz_sub_idx=$((fuzz_sub_idx + 1))
    fi
   fi
  done

  if [ $no_fuzz_cleanup = 0 ] ; then
   crashes=`ls $fuzz_dir | wc -w`
   if [ $crashes = 0 ] ; then
    rm -rf $fuzz_dir
   fi
  fi

  #we still run the subtest in fuzz mode, since further subtests may use the output of this test
 fi

echo "" > $log_subtest
echo "*** Subtest \"$2\": executing \"$1\" ***" >> $log_subtest

timeout_args=""
if [ $enable_timeout != 0 ] ; then
timeout_args="$GNU_TIMEOUT $test_timeout"
fi

$timeout_args $GNU_TIME -o $stat_subtest -f ' EXECUTION_STATUS="OK"\n RETURN_STATUS=%x\n MEM_TOTAL_AVG=%K\n MEM_RESIDENT_AVG=%t\n MEM_RESIDENT_MAX=%M\n CPU_PERCENT=%P\n CPU_ELAPSED_TIME=%E\n CPU_USER_TIME=%U\n CPU_KERNEL_TIME=%S\n PAGE_FAULTS=%F\n FILE_INPUTS=%I\n SOCKET_MSG_REC=%r\n SOCKET_MSG_SENT=%s' $1 >> $log_subtest 2>&1
rv=$?

echo "SUBTEST_NAME=$2" >> $stat_subtest
echo "SUBTEST_IDX=$subtest_idx" >> $stat_subtest

#regular error, check if this is a negative test.
if [ $rv -eq 1 ] ; then
 if [ $single_test = 1 ] ; then
  negative_test_stderr=$RULES_DIR/$TEST_NAME-stderr.txt
 else
  negative_test_stderr=$RULES_DIR/$TEST_NAME-$2-stderr.txt
 fi
 if [ -f $negative_test_stderr ] ; then
  #look for all lines in -stderr file, if one found consider this a success
  while read line ; do
   res_err=`grep -o "$line" $log_subtest`
   if [ -n "$res_err" ]; then
    echo "Negative test detected, reverting to success (found \"$res_err\" in stderr)" >> $log_subtest
    rv=0
    echo "" > $stat_subtest
    break
   fi
  #remove windows style endlines as they may cause some problems
  #also remove empty lines otherwise grep always matches
  done < <(tr -d '\r' <$negative_test_stderr | sed '/^$/d' )
 fi
fi

#override generated stats if error, since gtime may put undesired lines in output file which would break sourcing
if [ $rv != 0 ] ; then
echo "SUBTEST_NAME=$2" > $stat_subtest
echo "SUBTEST_IDX=$subtest_idx" >> $stat_subtest
mark_test_error
fi

echo "RETURN_VALUE=$rv" >> $stat_subtest
echo "COMMAND_LINE=\"$1\"" >> $stat_subtest

echo "" >> $log_subtest
ret=$rv
}
#end do_test

#@do_playback_test: checks for user input record if any, then launch MP4Client with $1 with dump_dur and dump_size video sec AVI recording, then checks audio and video hash of the dump and convert the video to MP4 when generating the hash. The results are logged as with do_test

do_playback_test ()
{

  if [ $# -gt 2 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@do_playback_test takes only two arguments - wrong call (first arg is $1)"
  fi

 if [ $strict_mode = 1 ] ; then
  if [ -f $TEST_ERR_FILE ] ; then
   return
  fi
 fi

 if [ $test_skip  = 1 ] ; then
  return
 fi

 if [ $single_test = 1 ] ; then
  FULL_SUBTEST="$TEST_NAME"
 else
  FULL_SUBTEST="$TEST_NAME-$2"
 fi
 AVI_DUMP="$TEMP_DIR/$FULL_SUBTEST-dump"

 args="$MP4CLIENT -avi 0-$dump_dur -out $AVI_DUMP -size $dump_size $1"

 ui_rec=$RULES_DIR/$FULL_SUBTEST-ui.xml

 if [ -f $ui_rec ] ; then
  args="$args -opt Validator:Mode=Play -opt Validator:Trace=$ui_rec"
 else
  args="$args -opt Validator:Mode=Disable"
 fi
 do_test "$args" $2

 #don't try hash if error
 if [ $ret != 0 ] ; then
  return
 fi

 if [ $skip_play_hash = 0 ] ; then
  #since AVI dump in MP4Client is based on real-time grab of multithreaded audio and video render
  #we may have interleaving differences in the resulting AVI :(
  #we generate a hash for both audio and video since we don't have a fix yet
  #furthermore this will allow figuring out if the error is in the video or the audio renderer
  $MP4BOX -aviraw video "$AVI_DUMP.avi" -out "$AVI_DUMP.video" > /dev/null 2>&1
  do_hash_test "$AVI_DUMP.video" "$2-avirawvideo"
  rm "$AVI_DUMP.video" 2> /dev/null

  $MP4BOX -aviraw audio "$AVI_DUMP.avi" -out "$AVI_DUMP.audio" > /dev/null 2>&1
  do_hash_test "$AVI_DUMP.audio" "$2-avirawaudio"
  rm "$AVI_DUMP.audio" 2> /dev/null
 fi

 if [ $do_store_video != 0 ] ; then
  if [ $generate_hash != 0 ] ; then
   ffmpeg_encode "$AVI_DUMP.avi" "$VIDEO_DIR_REF/$FULL_SUBTEST-ref.mp4"
  else
   ffmpeg_encode "$AVI_DUMP.avi" "$VIDEO_DIR/$FULL_SUBTEST-test.mp4"
  fi
 fi

if [ $keep_avi != 0 ] ; then
 if [ $generate_hash != 0 ] ; then
   mv "$AVI_DUMP.avi" "$VIDEO_DIR_REF/$FULL_SUBTEST-raw-ref.avi"
  else
   mv "$AVI_DUMP.avi" "$VIDEO_DIR/$FULL_SUBTEST-raw-test.avi"
  fi
else
  rm "$AVI_DUMP.avi" 2> /dev/null
fi

}
#end do_playback_test

#@do_hash_test: generates a hash for $1 file , compare it to HASH_DIR/$TEST_NAME$2.hash
do_hash_test ()
{

  if [ $# -gt 2 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@do_hash_test takes only two argument - wrong call (first arg is $1)"
  fi
 if [ $strict_mode = 1 ] ; then
  if [ -f $TEST_ERR_FILE ] ; then
   return
  fi
 fi

 if [ $test_skip  = 1 ] ; then
  return
 fi
 log L_DEB "Generating hash for $1"

 if [ $disable_hash = 1 ] ; then
  return
 fi

 STATHASH_SH="$TEMP_DIR/$TEST_NAME-stathash-$2.sh"

 test_hash="$TEMP_DIR/$TEST_NAME-$2-test.hash"
 ref_hash="$HASH_DIR/$TEST_NAME-$2.hash"

 echo "HASH_TEST=$2" > $STATHASH_SH

 echo "Computing $1  ($2) hash: " >> $log_subtest
 file_to_hash="$1"

 # for text files, we remove potential CR chars
 # to prevent having different hashes on different platforms
 if [ -n "$(file -b $1 | grep text)" ] ||  [ ${1: -4} == ".lsr" ] ; then
  file_to_hash="to_hash_$(basename $1)"
  tr -d '\r' <  "$1" > "$file_to_hash"
 fi

 $MP4BOX -hash -std $file_to_hash > $test_hash 2>> $log_subtest

 if [ "$file_to_hash" != "$1" ]; then
  rm "$file_to_hash"
 fi

 if [ $generate_hash = 0 ] ; then
  if [ ! -f $ref_hash ] ; then
   echo "HASH_NOT_FOUND=1" >> $STATHASH_SH
   return
  fi

  echo "HASH_NOT_FOUND=0" >> $STATHASH_SH

  $DIFF $test_hash $ref_hash > /dev/null
  rv=$?

  if [ $rv != 0 ] ; then
   fhash=`hexdump -ve '1/1 "%.2X"' $ref_hash`
   echo "Hash fail, ref hash $ref_hash was $fhash"  >> $log_subtest
   echo "HASH_FAIL=1" >> $STATHASH_SH
  else
   echo "Hash OK for $1"  >> $log_subtest
   echo "HASH_FAIL=0" >> $STATHASH_SH
  fi
  rm $test_hash

 else
  mv $test_hash $ref_hash
 fi
}
#end do_hash_test

#compare hashes of $1 and $2, return 0 if OK, error otherwise
do_compare_file_hashes ()
{
  if [ $# -gt 2 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@do_compare_file_hashes takes only two arguments - wrong call (first arg is $1)"
  fi
test_hash_first="$TEMP_DIR/$TEST_NAME-$(basename $1).hash"
test_hash_second="$TEMP_DIR/$TEST_NAME-$(basename $2).hash"

$MP4BOX -hash -std $1 > $test_hash_first 2> /dev/null
$MP4BOX -hash -std $1 > $test_hash_second 2> /dev/null
$DIFF $test_hash_first $test_hash_first > /dev/null

rv=$?
if [ $rv != 0 ] ; then
echo "Hash fail between $1 and $2"  >> $log_subtest
else
echo "Same Hash for $1 and $2"  >> $log_subtest
fi

rm $test_hash_first
rm $test_hash_second

return $rv

}
#end do_compare_file_hashes


#@ffmpeg_encode: encode source file $1 to $2 using default ffmpeg settings
ffmpeg_encode ()
{
  if [ $# -gt 2 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@ffmpeg_encode takes only two arguments - wrong call (first arg is $1)"
  fi
 #run ffmpeg in force overwrite mode
 $FFMPEG -y -i $1 -pix_fmt yuv420p -strict -2 $2 2> /dev/null
}
#end

#@single_test: performs a single test without hash with $1 command line and $2 test name
single_test ()
{
  if [ $# -gt 2 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@single_test takes only two arguments - wrong call (first arg is $1)"
  fi
test_begin "$2"
if [ $test_skip  = 1 ] ; then
return
fi
single_test=1
do_test "$1" "single"
test_end
}

#@single_playback_test: performs a single playback test with hashes with $1 command line and $2 test name
single_playback_test ()
{
  if [ $# -gt 2 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@single_playback_test takes only two arguments - wrong call (first arg is $1)"
  fi
test_begin "$2"
if [ $test_skip  = 1 ] ; then
return
fi
single_test=1
do_playback_test "$1" "play"
test_end
}


#@test_ui_test: if $test_ui is 1 records user input on $1 playback (10 sec) and stores in $RULES_DIR/$1-ui.xml. If $test_ui is 2, plays back the recorded stream
do_ui_test()
{
  if [ $# -gt 2 ] ; then
   log $L_ERR "> in test $TEST_NAME in script $current_script line $BASH_LINENO"
   log $L_ERR "	@test_ui_test takes one or two arguments - wrong call (first arg is $1)"
  fi

 if [ $test_ui = 0 ] ; then
  return
 fi

 if [ "$single_test_name" != "" ] && [ "$single_test_name" != "$TEST_NAME" ] ; then
   log $L_DEB "skiping ui test $TEST_NAME"
   return
 fi

 src=$1
 if [ $# -gt 1 ] ; then
  FULL_SUBTEST="$TEST_NAME-$2"
 else
  FULL_SUBTEST="$TEST_NAME"
 fi

 SUBTEST=$2
 ui_stream=$RULES_DIR/$FULL_SUBTEST-ui.xml

 if [ $test_ui = 1 ] ; then
  if [ -f $ui_stream ]; then
   log $L_DEB "User input trace present for $FULL_SUBTEST - skipping"
   return
  fi
  echo "Recording user input for $FULL_SUBTEST"
  echo "Recording user input for $FULL_SUBTEST (file $src) into trace $ui_stream" >> $ALL_LOGS
  $MP4CLIENT -run-for $dump_dur -size $dump_size $src -no-save -opt Validator:Mode=Record -opt Validator:Trace=$ui_stream 2>> $ALL_LOGS
  rv=$?
 else
  if [ ! -f $ui_stream ]; then
   log $L_WAR "User input trace not found for $FULL_SUBTEST - skipping playback"
   return
  fi
  echo "Playing user input for $FULL_SUBTEST"
  echo "Playing user input for $FULL_SUBTEST (file $src) from trace $ui_stream" >> $ALL_LOGS
  dur=$(($dump_dur / $speed))
  $MP4CLIENT -run-for $dur -size $dump_size $src -speed $speed -no-save -opt Validator:Mode=Play -opt Validator:Trace=$ui_stream 2>> $ALL_LOGS
  rv=$?
 fi
 #regular error, check if this is a negative test.
 if [ $rv != 0 ] ; then
  log $L_ERR "Error executing UI test for $FULL_SUBTEST (source file $src - test name $TEST_NAME)"
#  if [ $strict_mode = 1 ] ; then
#   exit
#  fi
 fi
}
#end test_ui_test


#start of our tests
start=`$GNU_DATE +%s%N`
start_date="$(date '+%d/%m/%Y %H:%M:%S')"

if [ $generate_hash = 1 ] ; then
 log $L_INF "Generating Test Suite SHA-1 Hashes"
elif [ $do_clean = 1 ] ; then
 log $L_INF "Cleaning Test Suite"
elif [ $check_only = 1 ] ; then
 log $L_INF "Checking Test Suite Names"
elif [ $global_test_ui = 1 ] ; then
 log $L_INF "Generating User Input traces"
elif [ $global_test_ui = 2 ] ; then
 log $L_INF "Playing User Input traces"
else
 log $L_INF "Evaluating Test Suite"
fi

print_end()
{
end=`$GNU_DATE +%s%N`
runtime=$((end-start))

ms=$(($runtime / 1000000))
secs=$(($ms / 1000))
ms=$(($ms - $secs*1000))
h=$(($secs / 3600))
secs=$(($secs - $h*3600))
m=$(($secs / 60))
secs=$(($secs - $m*60))

printf "$1 in %02d:%02d:%02d:%03d\n" $h $m $secs $ms
}

#gather all tests reports and build our final report
finalize_make_test()
{

#we are cleaning, nothing to do
if [ $do_clean != 0 ] ; then
 print_end "Cleanup done"
 return
fi

#ui tests nothing to do
if [ $global_test_ui != 0 ] ; then
 print_end "UI Tests done"
 return
fi

#create logs and final report
echo "Logs for GPAC test suite - execution date $start_date" > $ALL_LOGS

echo '<?xml version="1.0" encoding="UTF-8"?>' > $ALL_REPORTS
echo '<?xml-stylesheet href="stylesheet.xsl" type="text/xsl"?>' >> $ALL_REPORTS
echo "<GPACTestSuite version=\"$VERSION\" platform=\"$platform\" start_date=\"$start_date\" end_date=\"$(date '+%d/%m/%Y %H:%M:%S')\">" >> $ALL_REPORTS


if [ $erase_temp_dir != 0 ] ; then
   rm -rf $TEMP_DIR/* 2> /dev/null
fi

#count all tests using generated -stats.sh
TESTS_SKIP=0
TESTS_TOTAL=0
TESTS_DONE=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_LEAK=0
TESTS_EXEC_NA=0

SUBTESTS_FAIL=0
SUBTESTS_EXEC_NA=0
SUBTESTS_DONE=0
SUBTESTS_LEAK=0
SUBTESTS_HASH=0
SUBTESTS_HASH_FAIL=0
SUBTESTS_HASH_MISSING=0

for i in $LOGS_DIR/*-stats.sh ; do
if [ -f $i ] ; then

#reset stats
TEST_SKIP=0
TEST_EXEC_NA=0
SUBTESTS_LEAK=0
NB_HASH_SUBTESTS=0
NB_HASH_SUBTESTS_MISSING=0
NB_HASH_SUBTESTS_FAIL=0
NB_SUBTESTS=0

#load stats
source $i

#test not run due to error in strict mode
if [ $TEST_SKIP = 2 ] ; then
rm -f $i > /dev/null
continue;
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ $TEST_SKIP = 0 ] ; then
 TESTS_DONE=$((TESTS_DONE + 1))
cp $i "test.txt"
else
 TESTS_SKIP=$((TESTS_SKIP + $TEST_SKIP))
fi

if [ $TEST_FAIL = 0 ] ; then
  if [ $TEST_EXEC_NA = 0 ] && [ $SUBTESTS_LEAK = 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    rm -f $i > /dev/null
    if [ $TEST_EXEC_NA != 0 ] ; then
      TESTS_EXEC_NA=$((TESTS_EXEC_NA + 1))
    else
      TESTS_LEAK=$((TESTS_LEAK + 1))
    fi
  fi
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  rm -f $i > /dev/null
fi


SUBTESTS_FAIL=$((SUBTESTS_FAIL + $TEST_FAIL))
SUBTESTS_EXEC_NA=$((SUBTESTS_EXEC_NA + $TEST_EXEC_NA))
SUBTESTS_DONE=$((SUBTESTS_DONE + $NB_SUBTESTS))
SUBTESTS_LEAK=$((SUBTESTS_LEAK + $SUBTESTS_LEAK))
SUBTESTS_HASH=$((SUBTESTS_HASH + $NB_HASH_SUBTESTS))
SUBTESTS_HASH_FAIL=$((SUBTESTS_HASH_FAIL + $NB_HASH_SUBTESTS_FAIL))
SUBTESTS_HASH_MISSING=$((SUBTESTS_HASH_MISSING + $NB_HASH_SUBTESTS_MISSING))

fi

done

echo "<TestSuiteResults NumTests=\"$TESTS_TOTAL\" NumSubtests=\"$SUBTESTS_DONE\" TestsPassed=\"$TESTS_PASSED\" TestsFailed=\"$TESTS_FAILED\" TestsLeaked=\"$TESTS_LEAK\" TestsUnknown=\"$TESTS_EXEC_NA\" HashFailed=\"$SUBTESTS_HASH_FAIL\" HashMissing=\"$SUBTESTS_HASH_MISSING\" />" >> $ALL_REPORTS

#gather all failed reports first
for i in $LOGS_DIR/*-failed.xml; do
 if [ -f $i ] ; then
  cat $i >> $ALL_REPORTS
  echo "" >> $ALL_REPORTS
  rm $i
 fi
done

#gather all new reports
for i in $LOGS_DIR/*-passed-new.xml; do
 if [ -f $i ] ; then
  cat $i >> $ALL_REPORTS
  echo "" >> $ALL_REPORTS
  #move new report to final name
  n=${i%"-new.xml"}
  n="$n.xml"
  mv "$i" "$n"
 fi
done

echo '</GPACTestSuite>' >> $ALL_REPORTS

#cat all logs
for i in $LOGS_DIR/*-logs.txt-new; do
 if [ -f $i ] ; then
  cat $i >> $ALL_LOGS
  echo "" >> $ALL_LOGS
  #move new report to final name
  n=${i%".txt-new"}
  n="$n.txt"
  mv "$i" "$n"
 fi
done

if [ $TESTS_TOTAL = 0 ] ; then
log $L_INF "No tests executed"
else


pc1=$((100*TESTS_DONE/TESTS_TOTAL))
pc2=$((100*TESTS_SKIP/TESTS_TOTAL))
log $L_INF "Number of Tests $TESTS_TOTAL - $SUBTESTS_DONE subtests - Executed: $TESTS_DONE ($pc1 %) - Cached: $TESTS_SKIP ($pc2 %)"


if [ $TESTS_DONE = 0 ] ; then
 TESTS_DONE=$TESTS_TOTAL
fi
if [ $SUBTESTS_DONE = 0 ] ; then
 SUBTESTS_DONE=$TESTS_TOTAL
fi

 pc=$((100*TESTS_PASSED/TESTS_TOTAL))
 log $L_INF "Tests passed $TESTS_PASSED ($pc %) - $SUBTESTS_DONE sub-tests"

 # the follwing % are in subtests
 if [ $SUBTESTS_FAIL != 0 ] ; then
  pc=$((100*SUBTESTS_FAIL/SUBTESTS_DONE))
  log $L_ERR "Tests failed $TESTS_FAILED ($pc % of subtests)"
 fi

 if [ $SUBTESTS_LEAK != 0 ] ; then
  pc=$((100*SUBTESTS_LEAK/SUBTESTS_DONE))
  log $L_WAR "Tests Leaked $TESTS_LEAK ($pc % of subtests)"
 fi

 if [ $SUBTESTS_EXEC_NA != 0 ] ; then
  pc=$((100*SUBTESTS_EXEC_NA/SUBTESTS_DONE))
  log $L_WAR "Tests Unknown $TESTS_EXEC_NA ($pc % of subtests)"
 fi

 if [ $SUBTESTS_HASH_FAIL != 0 ] ; then
  pc=$((100*SUBTESTS_HASH_FAIL/SUBTESTS_DONE))
  log $L_WAR "Tests HASH total $SUBTESTS_HASH - fail $SUBTESTS_HASH_FAIL ($pc % of subtests)"
 fi

 if [ $SUBTESTS_HASH_MISSING != 0 ] ; then
  pc=$((100*SUBTESTS_HASH_MISSING/$SUBTESTS_HASH))
  log $L_WAR "Missing hashes $SUBTESTS_HASH_MISSING / $SUBTESTS_HASH ($pc % hashed subtests)"
 fi


fi

print_end "Generation done"

} #end finalize_make_test



# trap ctrl-c and generate reports
trap ctrl_c_trap INT

ctrl_c_trap() {
	echo "CTRL-C trapped - cleanup and building up reports"
	local pids=$(jobs -pr)
	[ -n "$pids" ] && kill $pids
	finalize_make_test
	exit
}

# disable nullglobing in case sub-scripts aren't made for it
shopt -u nullglob

#run our tests
if [ -n "$url_arg" ] ; then
 current_script=$url_arg
 source $url_arg
else
 for i in $SCRIPTS_DIR/*.sh ; do
  if [ $verbose = 1 ] ; then
   log $L_DEB "Source script: $i"
  fi
  current_script=$i
  source $i
  cd $main_dir
  #break if error and error
  if [ $strict_mode = 1 ] ; then
   #wait for all tests to be done before checking error marker
   wait
   if [ -f $TEST_ERR_FILE ] ; then
    break
   fi
  fi
 done
fi

#wait for all tests to be done, since some tests may use subshells
wait

if [ $check_only != 0 ] ; then
 rm -rf $TEMP_DIR/* 2> /dev/null
 exit
fi


finalize_make_test




