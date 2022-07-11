#!/usr/bin/env bash
set -e -o pipefail

BASE_DIR=$(realpath "$(dirname "$BASH_SOURCE")")
POOL_DIR="$(dirname "$BASE_DIR")/pool"
PROCESSED_DEB=$BASE_DIR/processed_deb
mkdir -p $PROCESSED_DEB
echo $POOL_DIR
Dists_DIR="$(dirname "$BASE_DIR")/dists"
REPO_JSON="$(dirname "$BASE_DIR")/repo.json"
arch_array=("aarch64" "arm" "i686" "x86_64")
components_array=($(jq -r .[].name  $REPO_JSON | tr '\n' ' '))
# Info being add into release file
ORIGIN="Termux-user-repository"
Suite="tur-packages"
Codename="tur-packages"
Architectures="aarch64 arm i686 x86_64"
Components=$(for i in "${components_array[@]}";do echo -n "$i ";done)
Description="Created with love for Termux community"

download_unprocessed_debs() {
    pushd $BASE_DIR
    rm -rf ./*.tar
    gh release download -R termux-user-repository/tur 0.1 -p "*.tar"
    popd
    
}
create_dist_structure() {
    echo "Creating dist structure"
    # remove all files and dir in dists.
    rm -rf $Dists_DIR
    mkdir -p $Dists_DIR
    mkdir -p $POOL_DIR
    mkdir -p $Dists_DIR/$Suite
    ## component dir.
    for comp in "${components_array[@]}";do
        mkdir -p $Dists_DIR/$Suite/$comp 
        mkdir -p $Dists_DIR/$Suite/$comp/binary-{aarch64,arm,i686,x86_64}
        ## pool direcectory if not exist.
        mkdir -p $POOL_DIR/$comp
    done



}
# add packages in pool. Not package actually, it just write packages metadata in pool.
add_package_metadata() {
    echo "Package metadata"
    cd $BASE_DIR
    rm -rf debs
    for tar_file in ./*.tar;
    do
        echo "processing $tar_file"
        tar -xf $tar_file
        
        if test -f debs/built*.txt;then
            repo_component=$(ls debs/built*.txt | cut -d_ -f2)
        else
            continue
        fi
        

        for deb_file in debs/*.deb;do
            deb_file=$(basename $deb_file)
            echo "scanning $deb_file"
            dpkg-scanpackages debs/$deb_file >| $POOL_DIR/$repo_component/$deb_file 
            ## update Filename: indices to relative path
            sed -i "/Filename:/c\Filename: pool/$repo_component/$deb_file" $POOL_DIR/$repo_component/$deb_file
        done
        mv -f debs/* $PROCESSED_DEB
    done
}
remove_old_version() {
    echo "Remove old version: Fix me"
}
create_packages() {
    echo "creating package file. "
    for comp in "${components_array[@]}";do
        echo "creating packages for $comp components"
        pushd $POOL_DIR/$comp
        for arch in "${arch_array[@]}";do
            count_deb_metadata_file=$(find . -name "./*{$arch,all}.deb" 2> /dev/null | wc -l)
            if [[ $count_deb_metadata_file == 0 ]];then
                continue
            fi
            pwd
            cat ./*{$arch,all}.deb 2>/dev/null >| $Dists_DIR/$Suite/$comp/binary-${arch}/Packages
            gzip -9k $Dists_DIR/$Suite/$comp/binary-${arch}/Packages
            echo "packages file created for $comp $arch"
        done
    done
}

add_general_info() {
    release_file_path=$1
    date_=$(date -uR)
    Arch=$2
    if [ $Arch == "all" ];then
        Arch=$Architectures
    fi
    cat > $release_file_path <<-EOF
Origin: $ORIGIN $Codename
Label: $ORIGIN $Codename
Suite: $Suite
Codename: $Codename
Date: $date_
Architectures: $Arch
Components: "$Components"
Description: $Description
EOF
}

generate_release_file() {
    r_file=$Dists_DIR/$Suite/Release
    rm -f $r_file
    touch $r_file
    cd $Dists_DIR/$Suite

    # add general info in main release file
    add_general_info $r_file "all"
    sums_array=("MD5" "SHA1" "SHA256" "SHA512")
    
    for sum in "${sums_array[@]}";do
        case $sum in
            MD5) 
                checksum=md5sum
                ;;
            SHA1)
                checksum=sha1sum
                ;;
            SHA256)
                checksum=sha256sum
                ;;
            SHA512)
                checksum=sha512sum
                ;;
            *)
                echo '...'
                exit 1
        esac
        echo "processing $sum"
        echo "${sum}:" >> $r_file
        for file in $(find $Components -type f);do
            generated_sum=$($checksum $file | cut -d' ' -f1 )
            filename_and_size=$(wc -c $file)
            echo " $generated_sum $filename_and_size" >> $r_file
            done
    done
            

}
sign_release_file() {
    cd $Dists_DIR/$Suite
    if [[ -n "$SEC_KEY" ]]; then
        echo "Importing key"
        echo -n "$SEC_KEY" | base64 --decode | gpg --import
    fi
    echo "Signing Release file"
    gpg --passphrase $SEC_PASS --batch --yes --pinentry-mode loopback -u 43EEC3A2934343315717FF6F6A5C550C260667D1 -bao ./Release.gpg Release
    gpg --passphrase $SEC_PASS --batch --yes --pinentry-mode loopback -u 43EEC3A2934343315717FF6F6A5C550C260667D1 --clear-sign --output InRelease Release
}
#download_unprocessed_debs
create_dist_structure
add_package_metadata
remove_old_version
create_packages
generate_release_file
sign_release_file
