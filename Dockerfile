FROM mcristinagrosu/bigstep_hdfs_datalake

RUN apk add --update alpine-sdk
RUN apk add libffi && apk add jq


# Install Spark 2.1.0
RUN cd /opt && wget http://d3kbcqa49mib13.cloudfront.net/spark-2.1.0-bin-hadoop2.7.tgz
RUN tar xzvf /opt/spark-2.1.0-bin-hadoop2.7.tgz
RUN rm  /opt/spark-2.1.0-bin-hadoop2.7.tgz

# Spark pointers
ENV SPARK_HOME /opt/spark-2.1.0-bin-hadoop2.7
ENV R_LIBS_USER $SPARK_HOME/R/lib:/opt/conda/envs/ir/lib/R/library:/opt/conda/lib/R/library
ENV PYTHONPATH $SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.8.2.1-src.zip

RUN mv spark-2.1.0-bin-hadoop2.7 /opt/ && mkdir -p /user && mkdir -p /user/notebooks && mkdir -p /user/datasets

ADD entrypoint.sh /
ADD core-site.xml.datalake /opt/spark-2.1.0-bin-hadoop2.7/conf/
RUN chmod 777 /entrypoint.sh
ADD spark-defaults.conf /opt/spark-2.1.0-bin-hadoop2.7/conf/spark-defaults.conf.template

ENV HADOOP_HOME /opt/hadoop
ENV HADOOP_CONF_DIR /opt/hadoop/etc/hadoop

ENV CONDA_DIR /opt/conda
ENV PATH $CONDA_DIR/bin:$PATH
ENV PATH $PATH:/$SPARK_HOME/bin/

RUN cd /opt && \
    wget https://repo.continuum.io/miniconda/Miniconda2-4.1.11-Linux-x86_64.sh && \
     /bin/bash Miniconda2-4.1.11-Linux-x86_64.sh -b -p $CONDA_DIR && \
     rm -rf Miniconda2-4.1.11-Linux-x86_64.sh 

RUN export PATH=$PATH:/$CONDA_DIR/bin

# Install Jupyter notebook 
RUN $CONDA_DIR/bin/conda install --yes \
    'notebook' && \
    $CONDA_DIR/bin/conda clean -yt
    
RUN $CONDA_DIR/bin/jupyter notebook  --generate-config

RUN $CONDA_DIR/bin/conda install --yes nb_conda
RUN $CONDA_DIR/bin/python -m nb_conda_kernels.install --disable --prefix=$CONDA_DIR && \
    $CONDA_DIR/bin/conda clean -yt
RUN jupyter-nbextension enable nb_conda --py --sys-prefix
RUN jupyter-serverextension enable nb_conda --py --sys-prefix
RUN jupyter-nbextension enable nbpresent --py --sys-prefix
RUN jupyter-serverextension enable nbpresent --py --sys-prefix

#Install Scala Spark kernel
ENV SBT_VERSION 0.13.11
ENV SBT_HOME /usr/local/sbt
ENV PATH ${PATH}:${SBT_HOME}/bin

# Install sbt
RUN curl -sL "http://dl.bintray.com/sbt/native-packages/sbt/$SBT_VERSION/sbt-$SBT_VERSION.tgz" | gunzip | tar -x -C /usr/local && \
    echo -ne "- with sbt $SBT_VERSION\n" >> /root/.built

RUN cd /tmp && \
    curl -sL "http://dl.bintray.com/sbt/native-packages/sbt/$SBT_VERSION/sbt-$SBT_VERSION.tgz" | gunzip | tar -x -C /usr/local && \
    echo -ne "- with sbt $SBT_VERSION\n" >> /root/.built &&\
    git clone https://github.com/apache/incubator-toree.git && \
    cd incubator-toree && \
    # git checkout 87a9eb8ad08406ce0747e92f7714d4eb54153293 && \
    # git checkout 7c1bfb6df7130477c558e69bbb518b0af364e06a && \
    make dist SHELL=/bin/bash APACHE_SPARK_VERDION=2.1.0 SCALA_VERSION=2.11 && \
    mv /tmp/incubator-toree/dist/toree /opt/toree-kernel && \
    chmod +x /opt/toree-kernel && \
    rm -rf /tmp/incubator-toree 
    
#Install Python3 packages
RUN $CONDA_DIR/bin/conda install --yes \
    'ipywidgets' \
    'pandas' \
    'matplotlib' \
    'scipy' \
    'seaborn' \
    'scikit-learn' && \
    $CONDA_DIR/bin/conda clean -yt

RUN $CONDA_DIR/bin/conda create --yes -p /opt/conda/envs/python3 python=3.5 ipython ipywidgets pandas matplotlib scipy seaborn scikit-learn
RUN bash -c '. activate python3 && \
    python -m ipykernel.kernelspec --prefix=/opt/conda && \
    . deactivate'
RUN jq --arg v "$CONDA_DIR/envs/python3/bin/python"         '.["env"]["PYSPARK_PYTHON"]=$v' /opt/conda/share/jupyter/kernels/python3/kernel.json > /tmp/kernel.json && \
     mv /tmp/kernel.json /opt/conda/share/jupyter/kernels/python3/kernel.json 

#Install R kernel and set up environment
RUN $CONDA_DIR/bin/conda config --add channels r
RUN $CONDA_DIR/bin/conda install --yes -c r r-essentials r-base r-irkernel r-irdisplay r-ggplot2 r-repr r-rcurl
RUN $CONDA_DIR/bin/conda create --yes  -n ir -c r r-essentials r-base r-irkernel r-irdisplay r-ggplot2 r-repr r-rcurl

RUN mkdir -p /opt/conda/share/jupyter/kernels/scala
COPY kernel.json /opt/conda/share/jupyter/kernels/scala/

RUN cd /root && wget http://central.maven.org/maven2/com/google/collections/google-collections/1.0/google-collections-1.0.jar

#Solution to readline library issues for SparkR context/session
RUN mv $CONDA_DIR/envs/python3/lib/libreadline.so.6 /opt/conda/envs/python3/lib/libreadline.so.6.tmp && \
    ln -s /usr/lib/libreadline.so.6 $CONDA_DIR/envs/python3/lib/libreadline.so.6
RUN mv $CONDA_DIR/envs/ir/lib/libreadline.so.6  $CONDA_DIR/envs/ir/lib/libreadline.so.6.tmp && \
    ln -s /usr/lib/libreadline.so.6 $CONDA_DIR/envs/ir/lib/libreadline.so.6
RUN mv $CONDA_DIR/lib/libreadline.so.6 $CONDA_DIR/lib/libreadline.so.6.tmp && \
    ln -s /usr/lib/libreadline.so.6 $CONDA_DIR/lib/libreadline.so.6
RUN mv $CONDA_DIR/pkgs/readline-6.2-2/lib/libreadline.so.6 $CONDA_DIR/pkgs/readline-6.2-2/lib/libreadline.so.6.tmp && \
    ln -s /usr/lib/libreadline.so.6 $CONDA_DIR/pkgs/readline-6.2-2/lib/libreadline.so.6
    
#Add Getting Started Notebooks
RUN wget https://www.dropbox.com/s/gfz7225ug0e6vwo/DataLab%20Getting%20Started%20in%20Scala.ipynb?dl=1 -O /user/notebooks/DataLab\ Getting\ Started\ in\ Scala.ipynb
RUN wget https://www.dropbox.com/s/rgriprne2r8hin7/DataLab%20Getting%20Started%20in%20R.ipynb?dl=1 -O /user/notebooks/DataLab\ Getting\ Started\ in\ R.ipynb
RUN wget https://www.dropbox.com/s/ih0xie29djlgzzo/DataLab%20Getting%20Started%20in%20Python.ipynb?dl=1 -O /user/notebooks/DataLab\ Getting\ Started\ in\ Python.ipynb

#Add cairo-dev for R notebook
RUN apk add cairo-dev

# Add hive-site.xml conf for metastore configuration
ADD hive-site.xml /opt/spark-2.1.0-bin-hadoop2.7/conf/

# Add PostgreSQL client to be used to configure a remote PostgreSQL database
ENV LANG en_US.utf8
ENV PG_MAJOR 9.6
ENV PG_VERSION 9.6.1
ENV PG_SHA256 e5101e0a49141fc12a7018c6dad594694d3a3325f5ab71e93e0e51bd94e51fcd

RUN set -ex \
	\
	&& apk add --no-cache --virtual .fetch-deps \
		ca-certificates \
		openssl \
		tar \
	\
	&& wget -O postgresql.tar.bz2 "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2" \
	&& echo "$PG_SHA256 *postgresql.tar.bz2" | sha256sum -c - \
	&& mkdir -p /usr/src/postgresql \
	&& tar \
		--extract \
		--file postgresql.tar.bz2 \
		--directory /usr/src/postgresql \
		--strip-components 1 \
	&& rm postgresql.tar.bz2 \
	\
	&& apk add --no-cache --virtual .build-deps \
		bison \
		flex \
		gcc \
        libc-dev \
		libedit-dev \
		libxml2-dev \
		libxslt-dev \
		make \
		openssl-dev \
		perl \
		util-linux-dev \
		zlib-dev \
	\
	&& cd /usr/src/postgresql \
	&& ./configure \
		--enable-integer-datetimes \
		--enable-thread-safety \
		--enable-tap-tests \
		--disable-rpath \
		--with-uuid=e2fs \
		--with-gnu-ld \
		--with-pgport=5432 \
		--with-system-tzdata=/usr/share/zoneinfo \
		--prefix=/usr/local \
		\
		--with-openssl \
		--with-libxml \
		--with-libxslt \
	&& make -j "$(getconf _NPROCESSORS_ONLN)" world \
	&& make install-world \
	&& make -C contrib install \
	\
	&& runDeps="$( \
		scanelf --needed --nobanner --recursive /usr/local \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| sort -u \
			| xargs -r apk info --installed \
			| sort -u \
	)" \
	&& apk add --no-cache --virtual .postgresql-rundeps \
		$runDeps \
		bash \
		su-exec \
		tzdata \
	&& apk del .fetch-deps .build-deps \
	&& cd / \
	&& rm -rf \
		/usr/src/postgresql \
		/usr/local/include/* \
		/usr/local/share/doc \
		/usr/local/share/man \
	&& find /usr/local -name '*.a' -delete

ENV PATH /usr/lib/postgresql/$PG_MAJOR/bin:$PATH
RUN apk add  musl 
RUN apk add --update libbz2 libcrypto1.0 expat libffi gdbm ncurses-libs readline sqlite-libs libssl1.0 zlib
RUN apk add python
RUN apk --no-cache add openssl
RUN apk --no-cache add --virtual ca-certificates

RUN apk --no-cache add python postgresql-libs && \
    apk --no-cache add --virtual build-dependencies python-dev gcc musl-dev postgresql-dev wget 

# Change Jupyter Logo
wget https://www.dropbox.com/s/ehlqagl5t0ed60h/logo.png?dl=1 -O logo.png

cp logo.png $CONDA_DIR/envs/python3/doc/global/template/images/logo.png
cp logo.png $CONDA_DIR/envs/python3/lib/python3.5/site-packages/notebook/static/base/images/logo.png
cp logo.png $CONDA_DIR/lib/python2.7/site-packages/notebook/static/base/images/logo.png
cp logo.png $CONDA_DIR/pkgs/notebook-4.2.3-py27_0/lib/python2.7/site-packages/notebook/static/base/images/logo.png
cp logo.png $CONDA_DIR/pkgs/qt-5.6.0-0/doc/global/template/images/logo.png
cp logo.png $CONDA_DIR/pkgs/notebook-4.2.3-py35_0/lib/python3.5/site-packages/notebook/static/base/images/logo.png
cp logo.png $CONDA_DIR/doc/global/template/images/logo.png
rm -rf logo.png

#        SparkMaster  SparkMasterWebUI  SparkWorkerWebUI REST     Jupyter Spark		Thrift
EXPOSE    7077        8080              8081              6066    8888      4040     88   10000

ENTRYPOINT ["/entrypoint.sh"]
