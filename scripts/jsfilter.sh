#test JSFilter as sink
single_test "$GPAC -i $MEDIA_DIR/auxiliary_files/enst_video.h264 $MEDIA_DIR/jsf/inspect.js" "jsf-inspect"


#test JSFilter as filter, forwarding to inspect
test_begin "jsf-inspect-fwd"
insp=$TEMP_DIR/inspect.txt
if [ $test_skip != 1 ] ; then
do_test "$GPAC -i $MEDIA_DIR/auxiliary_files/enst_video.h264 $MEDIA_DIR/jsf/inspect.js:fwd=true @ inspect:deep:log=$insp" "jsf-inspect-fwd"
do_hash_test $insp  "jsf-inspect"
fi
test_end


#test JSFilter as source (mostly for packet generation function testing)
test_begin "jsf-generate"
insp=$TEMP_DIR/inspect.txt
if [ $test_skip != 1 ] ; then
do_test "$GPAC $MEDIA_DIR/jsf/generate.js @ inspect:deep:log=$insp" "jsf-generate"
do_hash_test $insp  "jsf-generate"
fi
test_end


#test JSFilter as loader of filters, using a sink destination and a sink filter
test_begin "jsf-load-dest"
if [ $test_skip != 1 ] ; then
do_test "$GPAC $MEDIA_DIR/jsf/loader.js:in=$MEDIA_DIR/auxiliary_files/enst_video.h264:out=$TEMP_DIR/dump.264:f=inspect" "jsf-load-dest"
do_hash_test $TEMP_DIR/dump.264 "jsf-load-dest"
fi
test_end

#test JSFilter as loader of filters, using a sink filter
single_test "$GPAC $MEDIA_DIR/jsf/loader.js:in=$MEDIA_DIR/auxiliary_files/enst_video.h264:f=inspect" "jsf-load-filter"


# XHR test
single_test "$GPAC $MEDIA_DIR/jsf/xhr.js" "jsf-xhr"

# EVG generator
single_test "$GPAC $MEDIA_DIR/jsf/evg_src.js inspect:deep" "jsf-evg-src"