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
	echo "	$(basename $0) [option] -i <sound or movie file> -bucket <bucket name> -o <output file name>"
	echo "Options:"
	echo "	-h, --help			print this message."
	echo "	-lang <language code>		specify the language code. (default language code is \"ja-JP\")"
	echo ""
	echo "Example1: The following command transcribes Japanese sound or movie file and creates \"test-output.{json,txt}\"."
	echo "	This S3 Bucket, \"testid-bucket00001\", is created temporarily for the purpose of transcribe, and deleted after transcribe."
	echo ""
	echo "	$(basename $0) -i input-ja.mp4 -bucket testid-bucket00001 -o test-output"
	echo ""
	echo "Example2: The following command transcribes English sound or movie file and creates \"test-output.{json,txt}\"."
	echo ""
	echo "	$(basename $0) -lang en-US -i input-en.mp4 -bucket testid-bucket00001 -o test-output"
	exit
}


INPUT_FLAG=0; BUCKET_FLAG=0; OUTPUT_FLAG=0
while [ $# -gt 0 ]
do
	if [ "$1" == "-h" -o "$1" == "--help" ]; then
		print_usage
	elif [ "$1" == "-i" ]; then
		INPUT_FLAG=1; shift; INPUT_FILE="$1"; shift
	elif [ "$1" == "-bucket" ]; then
		BUCKET_FLAG=1; shift; BUCKET_NAME="$1"; shift
	elif [ "$1" == "-o" ]; then
		OUTPUT_FLAG=1; shift; OUTPUT_NAME="$1"; shift
	elif [ "$1" == "-lang"  ]; then
		shift; LANGUAGE_CODE="$1"; shift
	fi
done
if [ $INPUT_FLAG -eq 0 ]; then
	echo "Please specify input file, -i <sound or movie file>."
	echo "Please check '$(basename $0) -h' or '$(basename $0) --help'."
	exit
elif [ $BUCKET_FLAG -eq 0 ]; then
	echo "Please specify AWS S3 Bucket name, -bucket <bucket name>."
        echo "Please check '$(basename $0) -h' or '$(basename $0) --help'."
        exit
elif [ $OUTPUT_FLAG -eq 0 ]; then
	echo "Please specify output file name, -o <output file name>."
        echo "Please check '$(basename $0) -h' or '$(basename $0) --help'."
        exit
fi
TRANSCRIBE_DIR="$(cd "$(dirname "$0")"; pwd)"


ffmpeg -loglevel error -y -i "$INPUT_FILE" -vn -acodec copy transcripts-tmp.mp4 2> tmp.txt
if [ -s tmp.txt ]; then
        cat tmp.txt
        rm -f tmp.txt transcripts-tmp.mp4
        exit
fi
rm -f tmp.txt


aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION" 2> tmp.txt
if [ -s tmp.txt ]; then
	cat tmp.txt
	rm -f tmp.txt transcripts-tmp.mp4
	exit
fi


aws s3api put-public-access-block --bucket "$BUCKET_NAME" --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
aws s3 cp transcripts-tmp.mp4 s3://"$BUCKET_NAME"/ --acl private
rm -f tmp.txt transcripts-tmp.mp4


cat << EOF  > test-start-command.json
{
    "TranscriptionJobName": "test-job001", 
    "LanguageCode": "$LANGUAGE_CODE", 
    "MediaFormat": "mp4", 
    "Media": {
        "MediaFileUri": "s3://$BUCKET_NAME/transcripts-tmp.mp4"
    }
}
EOF
aws transcribe start-transcription-job \
     --region "$REGION" \
     --cli-input-json file://test-start-command.json 2> tmp.txt
if [ -s tmp.txt ]; then
        cat tmp.txt
	rm -f tmp.txt test-start-command.json
	aws s3api delete-object --bucket "$BUCKET_NAME" --key transcripts-tmp.mp4
	aws s3 rb s3://"$BUCKET_NAME"
        exit
fi
rm -f tmp.txt
echo "Now transcribing..."


while :
do
	sleep 10
	aws transcribe list-transcription-jobs --region "$REGION" |grep COMPLETED > completed-flag-check.txt
	if [ -s completed-flag-check.txt ]; then
		echo "Transcribing completed!"
		rm -f completed-flag-check.txt test-start-command.json
		break
	fi
done


aws transcribe get-transcription-job --transcription-job-name test-job001 1> tmp.json
sed -e "s/FileUri\":\ /FileUri\":\ \n/" tmp.json |grep https |sed -e "s/\"//g" > tmp-url.txt
rm -f asrOutput.json*; wget -q -i tmp-url.txt
mv -f asrOutput.json* "$OUTPUT_NAME".json
rm -f tmp.json tmp-url.txt


python3 "$TRANSCRIBE_DIR"/lib/extraction.py "$OUTPUT_NAME".json
sed -e "s/\[{'transcript'://" -e "s/\}\]//" tmp-asr-output.txt > tmp-asr-output.txte
if [ "$LANGUAGE_CODE" == "ja-JP" -o "$LANGUAGE_CODE" == "zh-CN" ]; then
	sed -e "s/。/。\n\n/g" tmp-asr-output.txte > "$OUTPUT_NAME".txt
else
	sed -e "s/\.\ /\.\n\n/g" tmp-asr-output.txte > "$OUTPUT_NAME".txt
fi
rm -f tmp-asr-output.txt*


aws transcribe delete-transcription-job --transcription-job-name test-job001
aws s3api delete-object --bucket "$BUCKET_NAME" --key transcripts-tmp.mp4
aws s3 rb s3://"$BUCKET_NAME"

