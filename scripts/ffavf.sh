
ffavf_test ()
{

test_begin "ffavf-$1"

if [ $test_skip  = 1 ] ; then
return
fi

#inspect result of filter graph, using packet number, dts, cts, sap and size
#we don't check CRC as we will likely not be bit-exact (codecs, afvilter behavior on various platforms/version)
myinspect=$TEMP_DIR/inspect.txt
do_test "$GPAC $2 @ inspect:interleave=false:deep:fmt=%pn%-%dts%-%cts%-%sap%-%size%%lf%:log=$myinspect -graph -stats" "inspect"
do_hash_test $myinspect "inspect"

test_end
}

#video -> video filter test
ffavf_test "v2v" "-i $MEDIA_DIR/auxiliary_files/enst_video.h264 ffavf:dump::f=negate"

#audio -> audio filter test
ffavf_test "a2a" "-i $MEDIA_DIR/auxiliary_files/enst_audio.aac ffavf:dump::f=acompressor"

#audio -> audio filter test forcing resampling and format
ffavf_test "a2a-cfg" "-i $MEDIA_DIR/auxiliary_files/enst_audio.aac ffavf:afmt=s16:sr=44100:dump::f=acompressor"

#audio -> video filter test with filter options, forcing pixel format
ffavf_test "a2v-cfg" "-i $MEDIA_DIR/auxiliary_files/enst_audio.aac ffavf:pfmt=yuv:dump::f=showspectrum=size=320x320"


#video+video -> video filter test
ffavf_test "vv2v" "-i $MEDIA_DIR/auxiliary_files/enst_video.h264:#ffid=a -i $MEDIA_DIR/auxiliary_files/logo.png:#ffid=b ffavf:dump::f=[a][b]overlay=main_w-overlay_w-10:main_h-overlay_h-10"
