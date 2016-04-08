# This is a template for GPAC test suite
#
#The following functions can be called for your test



# @ test_begin TESTNAME PAR1 ... PARN
#
# TESTNAME is the base identifier of your test, all output files will be called TESTNAME-*
# PAR1 ... PARN is the list of hashes you want to test. The names shall match the hash name in do_hash_test function
# this is used to skip hash regeneration when rebuilding the test suite references
#
# Each test generates
#  res/logs/TESTNAME-logs.txt log file containg all subtests
#  res/logs/TESTNAME-passed.xml file containg the stats for each subtest, as retrieved by time/gtime
#
# TESTNAME shall be unique. In case of doubts, run the test suite script with -check-name
#
# After calling test_begin, the $test_skip variable is set to 0 or 1
# When set to 1, indicates all subtests are OK in the cache and all subtests are being skipped. 
# A typical test with one subtest and no specific processing such as file creation and co will look like 
#
# test_begin TESTNAME
# do_test CMD_LINE1 "Name1"
# do_test CMD_LINE1 "Name2"
# test_end
#
# A typical test with several subtests starts therefore with 
#
# test_begin TESTNAME PAR1 ... PARN
# if [ $test_skip = 1 ] ; then
#   return
#  fi
# 
# #create some file or costly operation
# do_test CMD_LINE1 "Name1"
# #create some other file or costly operation
# do_test CMD_LINE1 "Name2"
# test_end
#




# @ do_test CMD_LINE SUBTEST_NAME
#
#you can call as many subtests using do_test function. 
#CMD_LINE: the command line to exectute
#SUBTEST_NAME: the subtest name as it appears in the logs and in the stats
#If needed, the return value is available in $ret
#
# This test looks for the files:
# $RULES_DIR/$TESTNAME-$SUBTEST-stderr.txt : specifies the list of accepted lines in error trace. If any of the line in this file is found, test will revert to success. This allows negative tests
#



# @ do_hash_test FILE PARX
#
#When generating the test suite reference, create a SHA-1 of FILE and stores it in $TESTNAME-$PARX.hash
#When testing, create a SHA-1 of FILE and compares it with $TESTNAME-$PARX.hash
#
#hash generation is optional, but it helps checking for regression in produced files among versions  
#


# @ do_playback_test FILE SUBTEST
#tests the playback of FILE by extracting it to a raw AVI and hashing both audio and video tracks. The subtest name for logs is SUBTEST.
# the generated hashes are
#  $TESTNAME-$SUBTEST-avirawvideo.hash
#  $TESTNAME-$SUBTEST-avirawaudio.hash
# the generated videos are
#  $TESTNAME-$SUBTEST-ref.mp4 reference video file (not used by test suite, only used for visual checking of the generation)
#  $TESTNAME-$SUBTEST-test.mp4  video file after test (not used by test suite, only used for debugging a test)
#Note: you only need to specify SUBTEST as a hash name in @test_begin, -avirawaudio and -avirawvideo are checked automatically
#
#This function uses overridable variables:
# $dump_size: by default "200x200" but can be overriden by your test
# $dump_dur: by default "10" seconds but can be overriden by your test
#
#The test uses do_test internally and can be used for negative testing as well
#
# This test looks for the files:
# $RULES_DIR/${basename $FILE.*}-$SUBTEST-ui.xml : specifies the recorded trace of UI interactions
#

# @ test_end
#
#Triggers the end of the test and writes all logs and statistics
#The function shall be called at the end of the test, except when $test_skip is 1
#

#
#subtests may be run in subscripts, for example
#
#
# test_begin TESTNAME
# do_test CMD_LINE1 "Name1" &
# do_test CMD_LINE1 "Name2" &
# test_end
#
#tests may also be run in subscript, for example
#
# function my_test {
#  test_begin $2
#  do_test $1 $2
#  test_end
# }
#
# my_test CMD_LINE1 "Name1" &
# my_test CMD_LINE2 "Name2" &
#

## Each test has its own log file $LOGS in which you can write (a lot is already in there, such as test name/data and all stderr)
#
# You may generate anything in $TEMP_DIR which is cleaned after running the test suite each test

