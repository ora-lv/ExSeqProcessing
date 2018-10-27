#!/bin/bash
# file: tests/test-runPipeline.sh

if [ ! -f tests/test-helper.sh ]; then
    echo "test-helper.sh not exist"
    exit
fi

. tests/test-helper.sh

SHUNIT2_SRC_DIR=~/works/shunit2
INPUT_IMAGE_DIR=/mp/nas1/share/ExSEQ/AutoSeq2/test-data/xy01/1_deconvolution-links
DECONVOLUTION_DIR=1_deconvolution
TEMP_DIR=./tmp-test
TEMP_DIR_TMP=${TEMP_DIR}-tmp

# =================================================================================================
oneTimeSetUp() {
    if [ ! -d test1_deconv ]; then
        cp -a $INPUT_IMAGE_DIR test1_deconv
    fi
    if [ ! -d vlfeat-0.9.20 ]; then
        ln -s ~/lib/matlab/vlfeat-0.9.20
    fi

    if [ ! -d test-results ]; then
        mkdir test-results
    fi

    if [ -f loadParameters.m ]; then
        rm -i loadParameters.m
    fi

    Result_dir=test-results/test-runPipeline-$(date +%Y%m%d_%H%M%S)
    mkdir $Result_dir

    for d in [2-6]_*
    do
        [ -e "$d" ] || continue
        rm -r "$d"
    done
    if [ -d logs ]; then
        rm -r logs
    fi

    sed -i.bak -e "s#\(params.tempDir\) *= *.*;#\1 = '${TEMP_DIR}';#" loadParameters.m.template
    mkdir -p "$TEMP_DIR"
    mkdir -p "$TEMP_DIR_TMP"

    TEMP_DIR=$(cd ${TEMP_DIR} && pwd)
    TEMP_DIR_TMP=$(cd ${TEMP_DIR_TMP} && pwd)
}

oneTimeTearDown() {
    if [ -d $DECONVOLUTION_DIR ]; then
        rm -r $DECONVOLUTION_DIR
    fi
    if [ -d test1_deconv ]; then
        rm -r test1_deconv
    fi
    if [ -h vlfeat-0.9.20 ]; then
        rm ./vlfeat-0.9.20
    fi

    for d in [2-6]_* test[2-6]_* test_report
    do
        [ -e "$d" ] || continue
        rm -r "$d"
    done
    if [ -d test_logs ]; then
        rm -r test_logs
    fi
    if [ -d "$TEMP_DIR" ]; then
        rm -r "$TEMP_DIR"
    fi
    if [ -d "$TEMP_DIR_TMP" ]; then
        rm -r "$TEMP_DIR_TMP"
    fi
}

# -------------------------------------------------------------------------------------------------

setUp() {
    if [ ! -d $DECONVOLUTION_DIR ]; then
        cp -a $INPUT_IMAGE_DIR $DECONVOLUTION_DIR
    fi

    if [ -f loadParameters.m ]; then
        rm loadParameters.m
    fi
}

tearDown() {
    for d in [2-6]_*
    do
        [ -e "$d" ] || continue
        rm -r "$d"
    done
    if [ -d logs ]; then
        rm -r logs
    fi

    if [ -f loadParameters.m ]; then
        rm loadParameters.m
    fi
}

# =================================================================================================
get_values_and_keys() {
    Value[ 1]=$(get_value_by_key "$Log" "# of rounds")
    Value[ 2]=$(get_value_by_key "$Log" "file basename")
    Value[ 3]=$(get_value_by_key "$Log" "reference round")
    Value[ 4]=$(get_value_by_key "$Log" "channels")
    Value[ 5]=$(get_value_by_key "$Log" "use GPU_CUDA")
    Value[ 6]=$(get_value_by_key "$Log" "intermediate image ext")
    Value[ 7]=$(get_value_by_key "$Log" "deconvolution images")
    Value[ 8]=$(get_value_by_key "$Log" "color correction images")
    Value[ 9]=$(get_value_by_key "$Log" "normalization images")
    Value[10]=$(get_value_by_key "$Log" "registration images")
    Value[11]=$(get_value_by_key "$Log" "puncta")
    Value[12]=$(get_value_by_key "$Log" "base calling")
    Value[13]=$(get_value_by_key "$Log" "vlfeat lib")
    Value[15]=$(get_value_by_key "$Log" "Temporal storage")
    Value[16]=$(get_value_by_key "$Log" "Reporting")
    Value[17]=$(get_value_by_key "$Log" "Log")
    Value[18]=$(get_value_by_key "$Log" "# of logical cores")
#    Value[19]=$(get_value_by_key "$Log" "down-sampling") # not change
    Value[20]=$(get_value_by_key "$Log" "color-correction")
    Value[21]=$(get_value_by_key "$Log" "normalization")
    Value[22]=$(get_value_by_key "$Log" "calc-descriptors")
    Value[23]=$(get_value_by_key "$Log" "reg-with-corres.") # not change
    Value[24]=$(get_value_by_key "$Log" "affine-transforms") # not change
#    Value[25]=$(get_value_by_key "$Log" "puncta-extraction")

    Key[1]=$(get_key_by_value "$Log" "setup-cluster")
    Key[2]=$(get_key_by_value "$Log" "color-correction")
    Key[3]=$(get_key_by_value "$Log" "normalization")
    Key[4]=$(get_key_by_value "$Log" "registration")
    Key[5]=$(get_key_by_value "$Log" "puncta-extraction")
    Key[6]=$(get_key_by_value "$Log" "base-calling")
    Key[7]=$(get_key_by_value "$Log" "calc-descriptors")
    Key[8]=$(get_key_by_value "$Log" "register-with-correspondences")
}

assert_all_default_values() {
    local skips=()

    if [ $# -ge 2 ]; then
        local check_mode=$1
        shift

        for arg in "$@"
        do
          if [ $check_mode = "skip" ]; then
              skips[$arg]=skip
          fi
        done
    fi

    if [ ! "${skips[1]}" = "skip" ]; then
        assertEquals 20 ${Value[1]}
    fi
    if [ ! "${skips[2]}" = "skip" ]; then
        assertEquals "exseqauto-xy01" "${Value[2]}"
    fi
    if [ ! "${skips[3]}" = "skip" ]; then
        assertEquals 5 ${Value[3]}
    fi
    if [ ! "${skips[5]}" = "skip" ]; then
        assertEquals "false" "${Value[5]}"
    fi
    if [ ! "${skips[6]}" = "skip" ]; then
        assertEquals "tif" "${Value[6]}"
    fi
    if [ ! "${skips[7]}" = "skip" ]; then
        assertEquals "$PWD/1_deconvolution" "${Value[7]}"
    fi
    if [ ! "${skips[8]}" = "skip" ]; then
        assertEquals "$PWD/2_color-correction" "${Value[8]}"
    fi
    if [ ! "${skips[9]}" = "skip" ]; then
        assertEquals "$PWD/3_normalization" "${Value[9]}"
    fi
    if [ ! "${skips[10]}" = "skip" ]; then
        assertEquals "$PWD/4_registration" "${Value[10]}"
    fi
    if [ ! "${skips[11]}" = "skip" ]; then
        assertEquals "$PWD/5_puncta-extraction" "${Value[11]}"
    fi
    if [ ! "${skips[12]}" = "skip" ]; then
        assertEquals "$PWD/6_base-calling" "${Value[12]}"
    fi
    if [ ! "${skips[13]}" = "skip" ]; then
        vlfeat_dir=$(cd ~/lib/matlab/vlfeat-0.9.20 && pwd)
        assertEquals "$vlfeat_dir" "${Value[13]}"
    fi
    if [ ! "${skips[15]}" = "skip" ]; then
        assertEquals "(on-memory)" "${Value[15]}"
    fi
    if [ ! "${skips[16]}" = "skip" ]; then
        reporting_dir=$(cd ./logs/imgs && pwd)
        assertEquals "$reporting_dir" "${Value[16]}"
    fi
    if [ ! "${skips[17]}" = "skip" ]; then
        log_dir=$(cd ./logs && pwd)
        assertEquals "$log_dir" "${Value[17]}"
    fi
}

assert_all_stages_run() {
    local skips=()

    if [ $# -ge 2 ]; then
        local check_mode=$1
        shift

        for arg in "$@"
        do
          if [ $check_mode = "skip" ]; then
              skips[$arg]=skip
          fi
        done
    fi

    for((i=1; i<=${#Key[*]}; i++))
    do
        if [ ! "${skips[$i]}" = "skip" ]; then
            assertEquals "" "${Key[$i]}"
        fi
    done
}

assert_all_stages_skip() {
    local skips=()

    if [ $# -ge 2 ]; then
        local check_mode=$1
        shift

        for arg in "$@"
        do
          if [ $check_mode = "skip" ]; then
              skips[$arg]=skip
          fi
        done
    fi

    for((i=1; i<=${#Key[*]}; i++))
    do
        if [ ! "${skips[$i]}" = "skip" ]; then
            assertEquals "skip" "${Key[$i]}"
        fi
    done
}

# =================================================================================================
testArgument001_check_all_stages_skip() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' > $Log 2>&1
    set +m

    local skip_cnt=$(grep -o 'Skip!' "$Log" | wc -l)
    assertEquals 6 $skip_cnt
}

testArgument002_default_values() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh > $Log 2>&1
    set +m

    get_values_and_keys

    assert_all_default_values
    assert_all_stages_run
}

# -------------------------------------------------------------------------------------------------
testArgument003_set_roundnum() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -N 8 > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=1
    assertEquals 8 ${Value[${value_id}]}

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.NUM_ROUNDS = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "${Value[${value_id}]}" "$param"
}

testArgument004_set_file_basename() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -b test_file_basename > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=2
    assertEquals "test_file_basename" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.FILE_BASENAME = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument005_set_reference_round() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -B 2 > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=3
    assertEquals 2 ${Value[${value_id}]}

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#regparams.FIXED_RUN = \(.*\);#\1#p' loadParameters.m)
    assertEquals "${Value[${value_id}]}" "$param"

    local param=$(sed -ne 's#params.REFERENCE_ROUND_WARP = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "${Value[${value_id}]}" "$param"

    local param=$(sed -ne 's#params.REFERENCE_ROUND_PUNCTA = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "${Value[${value_id}]}" "$param"
}

testArgument006_set_deconvolution_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -d test1_deconv > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=7
    assertEquals "$PWD/test1_deconv" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.deconvolutionImagesDir = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument007_set_color_correction_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -C test2_colorcor > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=8
    assertEquals "$PWD/test2_colorcor" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.colorCorrectionImagesDir = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument008_set_normalization_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -n test3_norm > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=9
    assertEquals "$PWD/test3_norm" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#regparams.INPUTDIR = \(.*\);#\1#p' loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"

    local param=$(sed -ne 's#params.normalizedImagesDir = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument009_set_registration_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -r test4_reg > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=10
    assertEquals "$PWD/test4_reg" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#regparams.OUTPUTDIR = \(.*\);#\1#p' loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"

    local param=$(sed -ne 's#params.registeredImagesDir = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument010_set_puncta_extraction_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -p test5_puncta > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=11
    assertEquals "$PWD/test5_puncta" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.punctaSubvolumeDir = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument011_set_set_base_calling_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -t test6_basecalling > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=12
    assertEquals "$PWD/test6_basecalling" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.basecallingResultsDir = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument012_set_vlfeat_lib_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -V ./vlfeat-0.9.20 > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=13
    vlfeat_dir=$(cd ./vlfeat-0.9.20 && pwd)
    assertEquals "$vlfeat_dir" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne "s#run('\(.*\)/toolbox.*#\1#p" ./startup.m)
    assertEquals "${Value[${value_id}]}" "$param"
}

testArgument013_set_reporting_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -i test_report > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=16
    reporting_dir=$(cd ./test_report && pwd)
    assertEquals "$reporting_dir" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.reportingDir = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument014_set_temp_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -T ${TEMP_DIR_TMP} > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=15
    temp_dir=$(cd ${TEMP_DIR_TMP} && pwd)
    assertEquals "$temp_dir" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.tempDir = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"

    local param=$(sed -ne 's#params.USE_TMP_FILES = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "true" "$param"
}

testArgument015_set_log_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -L test_logs > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=17
    log_dir=$(cd ./test_logs && pwd)
    assertEquals "$log_dir" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip
}

testArgument016_set_gpu_cuda_usage() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -G > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=5
    assertEquals "true" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip
}

testArgument017_set_hdf5_usage() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -H > $Log 2>&1
    set +m

    get_values_and_keys

    value_id=6
    assertEquals "h5" "${Value[${value_id}]}"

    # others are default values
    assert_all_default_values skip ${value_id}
    assert_all_stages_skip

    local param=$(sed -ne 's#params.IMAGE_EXT = \(.*\);#\1#p' ./loadParameters.m)
    assertEquals "'${Value[${value_id}]}'" "$param"
}

testArgument018_set_concurrency() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    ./runPipeline.sh -y -e ' ' -J 100,101,102,103,104,105 > $Log 2>&1
    set +m

    get_values_and_keys

#    local value=$(echo ${Value[19]} | sed -e 's/--, *\(.*\),--/\1/')
#    assertEquals "100" "${value}"

    local value=$(echo ${Value[20]} | sed -e 's/\([0-9]*\),.*/\1/')
    assertEquals "100" "${value}"

    local value=$(echo ${Value[21]} | sed -e 's/\([0-9]*\),.*/\1/')
    assertEquals "101" "${value}"

    local value=$(echo ${Value[22]} | sed -e 's/\([0-9]*\),.*/\1/')
    assertEquals "102" "${value}"

    local value=$(echo ${Value[23]} | sed -e 's/\([0-9]*\),.*/\1/')
    assertEquals "103" "${value}"

    local value=$(echo ${Value[24]} | sed -e 's/\([0-9]*\),.*/\1/')
    assertEquals "104" "${value}"

    # others are default values
    assert_all_default_values skip 20 21 22 23 24
    assert_all_stages_skip

#    local param=$(sed -ne 's#params.DOWN_SAMPLING_MAX_POOL_SIZE *= *\(.*\);#\1#p' ./loadParameters.m)
#    assertEquals "100" "$param"

    local param=$(sed -ne 's#params.COLOR_CORRECTION_MAX_RUN_JOBS *= *\(.*\);#\1#p' ./loadParameters.m)
    assertEquals "100" "$param"

    local param=$(sed -ne 's#params.NORM_MAX_RUN_JOBS *= *\(.*\);#\1#p' ./loadParameters.m)
    assertEquals "101" "$param"

    local param=$(sed -ne 's#params.CALC_DESC_MAX_RUN_JOBS *= *\(.*\);#\1#p' ./loadParameters.m)
    assertEquals "102" "$param"

    local param=$(sed -ne 's#params.REG_CORR_MAX_RUN_JOBS *= *\(.*\);#\1#p' ./loadParameters.m)
    assertEquals "103" "$param"

    local param=$(sed -ne 's#params.AFFINE_MAX_RUN_JOBS *= *\(.*\);#\1#p' ./loadParameters.m)
    assertEquals "104" "$param"
}

testArgument019_set_performance_profile() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local LogDir=$Result_dir/$curfunc
    local Log=$LogDir/output.log

    set -m
    ./runPipeline.sh -y -e 'setup-cluster' -P > $Log 2>&1
    set +m

    get_values_and_keys

    local skip_cnt=$(grep -o 'now recording' "$Log" | wc -l)
    assertEquals 1 $skip_cnt

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 1

    assertTrue 'no summary-top.txt' "[ -f logs/summary-top.txt ]"
    assertTrue 'no perf-measurement.ipynb' "[ -f logs/perf-measurement.ipynb ]"

    mv loadParameters.m logs $LogDir/
}

# -------------------------------------------------------------------------------------------------
testArgument100_skip_stage_setup_cluster() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'setup-cluster' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[1]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 1
}

testArgument101_skip_stage_color_correction() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'color-correction' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[2]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 2
}

testArgument102_skip_stage_normalization() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'normalization' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[3]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 3
}

testArgument103_skip_stage_registration() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'registration' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[4]}"
    assertEquals "skip" "${Key[7]}"
    assertEquals "skip" "${Key[8]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 4 7 8
}

testArgument104_skip_stage_puncta_extraction() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'puncta-extraction' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[5]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 5
}

testArgument105_skip_stage_base_calling() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'base-calling' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[6]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 6
}

testArgument106_skip_substage_calc_descriptors() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'calc-descriptors' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[7]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 7
}

testArgument107_skip_substage_register_with_correspondences() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'register-with-correspondences' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[8]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 8
}

testArgument108_skip_all_stages() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'setup-cluster,color-correction,normalization,registration,puncta-extraction,base-calling' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[1]}"
    assertEquals "skip" "${Key[2]}"
    assertEquals "skip" "${Key[3]}"
    assertEquals "skip" "${Key[4]}"
    assertEquals "skip" "${Key[5]}"
    assertEquals "skip" "${Key[6]}"
    assertEquals "skip" "${Key[7]}"
    assertEquals "skip" "${Key[8]}"

    # others are default values
    assert_all_default_values
}

testArgument109_skip_stage_normalization_and_substage_calc_descriptors() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'normalization,calc-descriptors' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[3]}"
    assertEquals "skip" "${Key[7]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 3 7
}

testArgument110_skip_stage_registration_and_substage_calc_descriptors() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -s 'registration,calc-descriptors' > $Log 2>&1
    set +m

    get_values_and_keys

    assertEquals "skip" "${Key[4]}"
    assertEquals "skip" "${Key[7]}"
    assertEquals "skip" "${Key[8]}"

    # others are default values
    assert_all_default_values
    assert_all_stages_run skip 4 7 8
}


# -------------------------------------------------------------------------------------------------
testArgument111_exec_stage_setup_cluster() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'setup-cluster' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 1
}

testArgument112_exec_stage_color_correction() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'color-correction' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 2
}

testArgument113_exec_stage_normalization() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'normalization' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 3
}

testArgument114_exec_stage_registration() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'registration' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 4 7 8
}

testArgument115_exec_stage_puncta_extraction() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'puncta-extraction' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 5
}

testArgument116_exec_stage_base_calling() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'base-calling' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 6
}

testArgument117_exec_substage_calc_descriptors() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'calc-descriptors' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 4 7
}

testArgument118_exec_substage_register_with_correspondences() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'register-with-correspondences' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 4 8
}

testArgument119_exec_stage_normalization_and_registration() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'normalization,registration' > $Log 2>&1
    set +m

    get_values_and_keys

    # others are default values
    assert_all_default_values
    assert_all_stages_skip skip 3 4 7 8
}

# -------------------------------------------------------------------------------------------------
testArgument200_Error_set_roundnum() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -N a > $Log 2>&1
    set +m

    message=$(grep "# of rounds is not number" "$Log" | wc -l)
    assertEquals 1 $message
}

testArgument201_Error_no_deconvolution_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    rm -r $DECONVOLUTION_DIR

    set -m
    echo 'n' | ./runPipeline.sh > $Log 2>&1
    set +m

    message=$(grep "No deconvolution dir" "$Log" | wc -l)
    assertEquals 1 $message

    cp -a $INPUT_IMAGE_DIR $DECONVOLUTION_DIR
}

testArgument202_Error_no_vlfeat_dir() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -V dummy_proj > $Log 2>&1
    set +m

    message=$(grep "No vlfeat library dir" "$Log" | wc -l)
    assertEquals 1 $message
}

testArgument203_Error_no_load_params_m_template() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    mv loadParameters.m.template{,-orig}

    set -m
    echo 'n' | ./runPipeline.sh > $Log 2>&1
    set +m

    message=$(grep "No 'loadParameters.m.template'" "$Log" | wc -l)
    assertEquals 1 $message

    mv loadParameters.m.template{-orig,}
}

testArgument204_Error_unacceptable_both_e_and_s_args() {
    local curfunc=${FUNCNAME[0]}
    mkdir ${Result_dir}/${curfunc}
    local Log=$Result_dir/$curfunc/output.log

    set -m
    echo 'n' | ./runPipeline.sh -e 'registration' -s 'calc-descriptors' > $Log 2>&1
    set +m

    message=$(grep "cannot use both -e and -s" "$Log" | wc -l)
    assertEquals 1 $message
}


# load and run shunit2
. $SHUNIT2_SRC_DIR/shunit2

