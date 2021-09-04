#!/bin/bash
#
# Copyright (C) 2021 Hirofumi Kojima
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


REGION=ap-northeast-1	# AWS Tokyo Region
LANGUAGE_CODE=ja-JP


print_usage ()
{
	echo "Description:"
	echo "	$(basename $0) is a transcription tool."
	echo "	$(basename $0) uses Amazon S3 and Amazon Transcribe, Speech-to-Text service."
	echo "	$(basename $0) requires the following commands, aws s3, aws transcribe, ffmpeg, python3."
	echo "Usage:"
	echo "	$(basename $0) [option] -i <sound or movie file> -o <output file name>"
	echo "Options:"
	echo "	-h, --help			print this message."
	echo "	-lang <language code>		specify the language code. (default language code is \"ja-JP\")"
	echo ""
	echo "Example1: The following command transcribes Japanese sound or movie file and creates \"test-output.{json,txt}\"."
	echo ""
	echo "	$(basename $0) -i input-ja.mp4 -o test-output"
	echo ""
	echo "Example2: The following command transcribes English sound or movie file and creates \"test-output.{json,txt}\"."
	echo ""
	echo "	$(basename $0) -lang en-US -i input-en.mp4 -o test-output"
	exit
}


# Random String
RS=$(cat /dev/urandom |base64 |tr -cd "a-z0-9" |fold -w 32 |head -n 1)


INPUT_FLAG=0; OUTPUT_FLAG=0
while [ $# -gt 0 ]
do
	if [ "$1" == "-h" -o "$1" == "--help" ]; then
		print_usage
	elif [ "$1" == "-i" ]; then
		INPUT_FLAG=1; shift; INPUT_FILE="$1"; shift
	elif [ "$1" == "-o" ]; then
		OUTPUT_FLAG=1; shift; OUTPUT_NAME="$1"; shift
	elif [ "$1" == "-lang"  ]; then
		shift; LANGUAGE_CODE="$1"; shift
	else
		shift
	fi
done
if [ $INPUT_FLAG -eq 0 ]; then
	echo "Please specify input file, -i <sound or movie file>."
	echo "Please check '$(basename $0) -h' or '$(basename $0) --help'."
	exit
elif [ $OUTPUT_FLAG -eq 0 ]; then
	echo "Please specify output file name, -o <output file name>."
        echo "Please check '$(basename $0) -h' or '$(basename $0) --help'."
        exit
fi
TRANSCRIBE_DIR="$(cd "$(dirname "$0")"; pwd)"


ffmpeg -loglevel error -y -i "$INPUT_FILE" -vn -acodec copy transcripts-tmp-$RS.mp4 2> tmp-$RS.txt
if [ -s tmp-$RS.txt ]; then
        cat tmp-$RS.txt
        rm -f tmp-$RS.txt transcripts-tmp-$RS.mp4
        exit
fi
rm -f tmp-$RS.txt


BUCKET_NAME=transcribe-$RS
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION" 2> tmp-$RS.txt
if [ -s tmp-$RS.txt ]; then
	cat tmp-$RS.txt
	rm -f tmp-$RS.txt transcripts-tmp-$RS.mp4
	exit
fi
rm -f tmp-$RS.txt


aws s3api put-public-access-block --bucket "$BUCKET_NAME" --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
aws s3 cp transcripts-tmp-$RS.mp4 s3://"$BUCKET_NAME"/ --acl private
rm -f transcripts-tmp-$RS.mp4


cat << EOF  > test-start-command-$RS.json
{
    "TranscriptionJobName": "test-job-$RS", 
    "LanguageCode": "$LANGUAGE_CODE", 
    "MediaFormat": "mp4", 
    "Media": {
        "MediaFileUri": "s3://$BUCKET_NAME/transcripts-tmp-$RS.mp4"
    }
}
EOF
aws transcribe start-transcription-job \
     --region "$REGION" \
     --cli-input-json file://test-start-command-$RS.json 2> tmp-$RS.txt
if [ -s tmp-$RS.txt ]; then
        cat tmp-$RS.txt
	rm -f tmp-$RS.txt test-start-command-$RS.json
	aws s3api delete-object --bucket "$BUCKET_NAME" --key transcripts-tmp-$RS.mp4
	aws s3 rb s3://"$BUCKET_NAME"
        exit
fi
rm -f tmp-$RS.txt
echo "Now transcribing..."


while :
do
	sleep 10
	aws transcribe list-transcription-jobs --region "$REGION" |grep COMPLETED > completed-flag-check-$RS.txt
	if [ -s completed-flag-check-$RS.txt ]; then
		echo "Transcribing completed!"
		rm -f test-start-command-$RS.json
		break
	fi
done


if [ -s completed-flag-check-$RS.txt ]; then

	aws transcribe get-transcription-job --transcription-job-name test-job-$RS 1> tmp-$RS.json
	sed -e "s/FileUri\":\ /FileUri\":\ \n/" tmp-$RS.json |grep https |sed -e "s/\"//g" > tmp-url-$RS.txt
	rm -f asrOutput.json*; wget -q -i tmp-url-$RS.txt
	mv -f asrOutput.json* "$OUTPUT_NAME".json
	rm -f tmp-$RS.json tmp-url-$RS.txt


	python3 "$TRANSCRIBE_DIR"/lib/extraction.py "$OUTPUT_NAME".json tmp-asr-output-$RS.txt
	sed -e "s/\[{'transcript'://" -e "s/\}\]//" tmp-asr-output-$RS.txt > tmp-asr-output-$RS.txte
	if [ "$LANGUAGE_CODE" == "ja-JP" -o "$LANGUAGE_CODE" == "zh-CN" ]; then
		sed -e "s/。/。\n\n/g" tmp-asr-output-$RS.txte > tmp-output-name-$RS.txt
	else
		sed -e "s/\.\ /\.\n\n/g" tmp-asr-output-$RS.txte > tmp-output-name-$RS.txt
	fi
	rm -f tmp-asr-output-$RS.txt*

	EOF=$(wc -l < tmp-output-name-$RS.txt |sed -e 's/\ //g' -e 's/\t//g')
	if [ $EOF -eq 1 ]; then
		cat tmp-output-name-$RS.txt |awk '{print substr($0, 3, length($0)-3)}' > "$OUTPUT_NAME".txt
	else
		cat tmp-output-name-$RS.txt |awk '
			{
				if(NR == 1){
					print substr($0, 3)
				}
				else if(NR == '$EOF'){
					print substr($0, 1, length($0)-1)
				}
				else{
					print $0
				}
			}
		'  > "$OUTPUT_NAME".txt
	fi
	rm -f tmp-output-name-$RS.txt

fi


rm -f completed-flag-check-$RS.txt
aws transcribe delete-transcription-job --transcription-job-name test-job-$RS
aws s3api delete-object --bucket "$BUCKET_NAME" --key transcripts-tmp-$RS.mp4
aws s3 rb s3://"$BUCKET_NAME"

