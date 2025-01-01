#  bash gcs_fuse_install.sh
[ -d "useful_scripts" ] && (cd useful_scripts && git pull && cd ..) || git clone https://github.com/OhadRubin/useful_scripts.git; bash useful_scripts/gcs_fuse_install.sh
# [ -d "useful_scripts" ] && (cd useful_scripts && git pull && cd ..) || git clone https://github.com/OhadRubin/useful_scripts.git; bash useful_scripts/detect_preempt.sh
# [ -d "useful_scripts" ] && (cd useful_scripts && git pull && cd ..) || git clone https://github.com/OhadRubin/useful_scripts.git; bash useful_scripts/setup_doc_ker.sh