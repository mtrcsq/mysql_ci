#!/bin/bash

#   error code list:
#   3     fail to initdb
#   4     fail to execute pg_ctl stop
#   5     fail to create directory or file
#   6     instance is running
#   7     instance is not running
#   8     instance exists
#   9     instance does not exist
#   10    instance exists in service
#   11    instance does not exists in service
#   12    can not find system configure file
#   13    fail to execute pg_ctl status
#   14    fail to execute pg_config
#   15    fail to execute reload
#   16    fail to execute pg_ctl start
#   17    serivce isn't owned by sequoiasql-postgresql
#   18    fail to get instance port
#   19    fail to execute createdb
#   20    fail to write file
#   21    svcname isn't in range ( 0, 65536 )
#   64    command line usage error
#   77    permission denied


OPTION=""
SD_MODE=fast
MYSQL_USER=sdbadmin
SYS_CONF_FILE=""
INST_NAME_LIST=""

function lack_para()
{
   local para_name=$1
   echo "sdb_mysql_ctl: no parameter \"$para_name\" specified" >&2
   echo 'Try "sdb_mysql_ctl --help" for more information.'
   exit 64
}

function err_para()
{
   local para_name=$1
   local para_value=$2
   echo "sdb_mysql_ctl: unrecognized $para_name \"$para_value\"" >&2
   echo 'Try "sdb_mysql_ctl --help" for more information.'
   exit 64
}

function check_num_para()
{
   local para_name=$1
   local para_value=$2

   local regex='^[0-9]+$'
   if ! [[ "$para_value" =~ $regex ]]; then
      echo "sdb_mysql_ctl: invalid value for parameter \"$para_name\": \"$para_value\"" >&2
      echo 'Try "sdb_mysql_ctl --help" for more information.'
      exit 64
   fi
}

function check_svcname_para()
{
   if [ $PORT -lt 1 -o $PORT -gt 65535 ]; then
      echo "ERROR: svcname isn't in range ( 0, 65536 )"
      exit 21
   fi
}

function check_opt_para()
{
   local para_value=$1
   for opt in $para_value
   do
      case "$opt" in
         -V | --version | '-?' | --help )
            echo "sdb_mysql_ctl: parameter \"OPTIONS\" is forbidden to include \"$opt\"" >&2
            echo 'Try "sdb_mysql_ctl --help" for more information.'
            exit 64
            ;;
      esac
   done
}

#The function will set global variable SYS_CONF_FILE
function get_system_conf_file()
{
   local cur_install_dir=$INSTALL_PATH
   local do_find_out=false

   for file in `find /etc/default -name "sequoiasql-mysql"`
   do
      . $file
      cd $INSTALL_DIR >> /dev/null 2>&1 && local sys_install_dir=`pwd` || sys_install_dir="$INSTALL_DIR"
      cd $cur_path >> /dev/null >&1
      if [ "$cur_install_dir" == "$sys_install_dir" ]
      then
         local do_find_out=true
         break
      fi
   done

   if [ $do_find_out == true ]
   then
      SYS_CONF_FILE=$file
   else
      echo "ERROR: No system configure file exist in /etc/default" >&2
      exit 12
   fi
}

function check_user()
{
   local operate_mode=$1

   . $SYS_CONF_FILE
   MYSQL_USER=$USER

   local cur_user=`whoami`
   if [ "$cur_user" != "$MYSQL_USER" -a "$cur_user" != "root" ]
   then
      echo "ERROR: sdb_mysql_ctl $operate_mode requires PGUSER [$MYSQL_USER] permission" >&2
      exit 77
   fi
}

# if root: change to pg user to execute command
# if pg user: execute command
function exec_cmd()
{
   local cmd="$1"
   local cur_user=`whoami`

   if [ $cur_user == "root" ]
   then
      su - $MYSQL_USER -c "export LD_LIBRARY_PATH=$INSTALL_DIR/lib;$cmd"
      return $?
   else
      eval "${cmd}"
      return $?
   fi
}

#check instance exists or not
function check_inst_exist()
{
   local inst_port=$1
   local inst_name=mysqld$1

   local inst_exist=$INSTALL_DIR/bin/mysqld_multi --defaults-file=$INSTALL_DIR/my.cnf report $inst_name

   if [[ $inst_exist =~ $inst_name ]]
   then
      echo "ERROR: instance $inst already exists" >&2
      exit 8
   else
      echo "ERROR: instance $inst does not exist" >&2
      exit 9
   fi
}

function parse_server_arguments() {
   for arg do
      case "$arg" in
         --basedir=*)   basedir=`echo "$arg" | sed -e 's/^[^=]*=//'`
            ;;
         --datadir=*)   datadir=`echo "$arg" | sed -e 's/^[^=]*=//'`
            ;;
         --port=*)      port=`echo "$arg" | sed -e 's/^[^=]*=//'`
            ;;
         --log_error=*) log_error=`echo "$arg" | sed -e 's/^[^=]*=//'`;;
      esac
   done
   printf "%-15s %-10s  %-45s %-45s\n" "mysqld"$port $port $datadir $log_error
}

function get_instnames()
{
   local i=0
   for line in `cat $INSTALL_DIR/my.cnf`
   do
      if [[ $line =~ ^\s*\[\s*(mysqld)([0-9]+)\s*\]\s*$ ]]
      then
         b=`echo $line | grep "mysqld[0-9]\+" -o`
         INST_NAME_LIST[i]=$b
         i=$(($i+1))
      fi
   done
}

#TODO
function modify_config()
{
}

function list_inst()
{
   printf "%-10s %-40s %-40s\n" "NAME" "PORT" "DATADIR" "LOGFILE"
   get_instnames
   local i=0
   for inst in ${INST_NAME_LIST[@]}
   do
      parse_server_arguments `$INSTALL_DIR/bin/my_print_defaults --defaults-file=$INSTALL_DIR/my.cnf ${inst}`
      i=$(($i+1))
   done
   printf "Total: %s\n" $i
}
#TODO
function add_inst()
{
   #check argument
   if [ ! -z $INST_PORT ]; then
      check_svcname_para
   fi
   check_inst_exist $INST_PORT

   echo "Adding instance mysqld$INST_PORT,port is $INST_PORT ..."
   #init database
   exec_cmd "$INSTALL_DIR/bin/mysqld --basedir=$INSTALL_DIR --datadir=$MYSQL_DATA --user=$USER"
   #write $INSTALL_DIR/my.cnf
   sed -i '$a\[mysqld$INST_PORT]'                  $INSTALL_DIR/my.conf
   sed -i '$a\port=$INST_PORT'                     $INSTALL_DIR/my.conf
   sed -i '$a\basedir=$INSTALL_DIR'                $INSTALL_DIR/my.conf
   sed -i '$a\datadir=$MYSQL_DATA'                 $INSTALL_DIR/my.conf
   sed -i '$a\pid-file=$MYSQL_PIDFILE'             $INSTALL_DIR/my.conf
   sed -i '$a\log_error=$MYSQL_LOGFILE'            $INSTALL_DIR/my.conf
   sed -i '$a\socket=$MYSQL_SOCKET'                $INSTALL_DIR/my.conf
   sed -i '$a\user=$USER'                          $INSTALL_DIR/my.conf
   
   #start instance
   start_inst $INST_PORT
   
   #install db plugin
   exec_cmd "$INSTALL_DIR/bin/mysql -u root --socket=$MYSQL_SOCKET -e \"install plugin sequoiadb soname 'ha_sequoiadb.so';\""
   sed -i '$a\default-storage-engine=SequoiaDB'            $INSTALL_DIR/my.conf
   sed -i '$a\sequoiadb_use_partition=ON'                  $INSTALL_DIR/my.conf
   sed -i '$a\haracter_set_server=utf8'                    $INSTALL_DIR/my.conf
   restart_inst $INST_PORT
   
   echo "ok"

}

function delete_inst()
{
   check_inst_exist $INST_PORT

   echo "Deleting instance $INST_NAME, port is $INST_PORT ..."

   #stop instance
   stop_inst $INST_PORT 1> /dev/null || exit $? #print stderr

   #delete file
   #TODO reade my.cnf 

   echo "ok"
}

function get_one_status()
{
   local port=$1

   check_inst_exist $port

   exec_cmd "$INSTALL_DIR/mysqldadmin -u root --port=$port --socket=$socket ping >> $PGLOG"
   ret=$?

   if [ $ret == 0 ]
   then
      # get pid
      local pid=`head -n 1 "$PID-FILE" 2>/dev/null`

      # print
      printf "%-10s %-10s %-10s %-40s %-40s\n" $inst $pid $port $DATADIR $LOGFILE
      return 0
   elif [ $ret == 3 ]
   then
      printf "%-10s %-10s %-10s %-40s %-40s\n" $inst "-" "-" $PGDATA $PGLOG
      return 3
   else
      echo "ERROR: Fail to query $inst status, please verify log $PGLOG" >&2
      exit 13
   fi
}

function get_status()
{
   local inst_list=""

   if [ -z $INST_NAME ]
   then
      inst_list=`list_inst | awk '{print $1}' | grep -vx PORT | grep -vx Total:`
   else
      inst_list=$INST_NAME
   fi

   printf "%-10s %-10s %-10s %-40s %-40s\n" "INSTANCE" "PID" "SVCNAME" "PGDATA" "PGLOG"

   local total_cnt=0
   local run_cnt=0
   for inst in $inst_list
   do
      get_one_status $inst
      local ret=$?

      test $ret -eq 0 && run_cnt=$(($run_cnt+1))
      total_cnt=$(($total_cnt+1))
   done

   printf "Total: %s; Run: %s\n" $total_cnt $run_cnt
}

function start_inst()
{
   local port=$1

   check_inst_exist $port
   local `$INSTALL_DIR/bin/my_print_defaults --defaults-file=$INSTALL_DIR/my.cnf mysqld${port}`

   #check instance start or not
   get_one_status $port > /dev/null
   if [ $? == 0 ]; then
      echo "port $port is already running"
      return 0
   fi

   #start
   echo "Starting instance mysqld$inst ..."
   exec_cmd "$INSTALL_DIR/bin/musqld_multi --defaults-file=$INSTALL_DIR/my.cnf start $port"
   if [ $? != 0 ]; then
      echo "ERROR: Fail to start, please verify log $MYSQLLOG" >&2
      return 16
   fi

   #check
   get_one_status $inst >> /dev/null
   local ret=$?

   if [ $ret == 0 ]
   then
      local pid=`head -n 1 "$DATADIR/mysqld.pid" 2>/dev/null`
      echo "ok (PID: $pid)"
      return 0
   elif [ $ret == 3 ]
   then
      echo "ERROR: Fail to start, please verify log $XXXX" >&2
      return 7
   else
      echo "ERROR: Fail to query status." >&2
      return 13
   fi
}

function start_all()
{
   local total_cnt=0
   local succ_cnt=0
   local fail_cnt=0
   local inst_list=`list_inst | awk '{print $2}' | grep -vx PORT | grep -vx Total:`
   for inst_port in $inst_list
   do
      start_inst $inst_port && succ_cnt=$(($succ_cnt+1)) || fail_cnt=$(($fail_cnt+1))
      total_cnt=$(($total_cnt+1))
   done

   echo "Total: $total_cnt; Succeed: $succ_cnt; Failed: $fail_cnt"

   test $total_cnt != $succ_cnt && exit 7
}

function stop_inst()
{
   local port=$1
   check_inst_exist $port

   #check instance start or not
   get_one_status $port > /dev/null
   if [ $? != 0 ]
   then
      echo "port $port is not running"
      return 0
   fi

   #stop
   local pid=`get_one_status $port | grep $port | awk '{print $2}'`
   echo "Stoping port $port (PID: $pid) ..."

   exec_cmd "$INSTALL_DIR/bin/musqld_multi --defaults-file=$INSTALL_DIR/my.cnf start $port >> $MYSQLLOG 2>&1"
   if [ $? != 0 ]; then
      echo "ERROR: Fail to stop, please verify log $MYSQLLOG" >&2
      return 4
   fi

   #check
   get_one_status $inst > /dev/null
   local ret=$?

   if [ $ret == 3 ]
   then
      echo "ok"
      return 0
   elif [ $ret == 0 ]
   then
      echo "ERROR: Fail to start, please verify log $MYSQLLOG" >&2
      return 7
   else
      echo "ERROR: Fail to query status." >&2
      return 13
   fi
}

function stop_all()
{
   local total_cnt=0
   local succ_cnt=0
   local fail_cnt=0

   local inst_list=`list_inst | awk '{print $2}' | grep -vx PORT | grep -vx Total:`
   for inst in $inst_list
   do
      stop_inst $inst && succ_cnt=$(($succ_cnt+1)) || fail_cnt=$(($fail_cnt+1))
      total_cnt=$(($total_cnt+1))
   done

   echo "Total: $total_cnt; Succeed: $succ_cnt; Failed: $fail_cnt"

   test $total_cnt != $succ_cnt && exit 6
}

function restart_inst()
{
   stop_inst $INST_PORT || exit $?
   start_inst $INST_PORT || exit $?
}

function build_help()
{
   echo "sdb_mysql_ctl is a utility to initialize, start, stop, or control a SequoiaSQL server."
   echo ""
   echo "Usage:"
   echo "  sdb_mysql_ctl listinst"
   echo "  sdb_mysql_ctl addinst    <PORT> [-o \"OPTIONS\"]"
   echo "  sdb_mysql_ctl delinst    <PORT>"
   echo "  sdb_mysql_ctl start      <PORT>"
   echo "  sdb_mysql_ctl startall"
   echo "  sdb_mysql_ctl stop       <PORT>"
   echo "  sdb_mysql_ctl stopall"
   echo "  sdb_mysql_ctl restart    <PORT>"
   echo "  sdb_mysql_ctl status     [PORT]"
   echo ""
   echo "Options:"
   echo "  -d datadir             location of the database storage area"
   echo "  -l log_error           write server log to LOGFILE"
   echo "  -f pid-file            location of the pid file"
   echo "  -s socket              socket file between client and server"
}

#Parse command line parameters
test $# -eq 0 && { build_help && exit 64; }

ARGS=`getopt -o hvd:l:f:s: --long help: -n 'sdb_mysql_ctl' -- "$@"`
ret=$?
test $ret -ne 0 && exit $ret

eval set -- "${ARGS}"

while true
do
   case "$1" in
      -d )             DEFINE_MYSQLDATA=true
                       MYSQL_DATA=$2
                       shift 2
                       ;;
      -l )             MYSQL_LOGFILE=$2
                       shift 2
                       ;;
      -f )             MYSQL_PIDFILE=$2
                       shift 2
                       ;;
      -s )             MYSQL_SOCKET=$2
                       shift 2
                       ;;
      -h | --help )    build_help
                       exit 0
                       ;;
      --)              shift
                       break
                       ;;
      *)               echo "Internal error!"
                       exit 64
                       ;;
   esac
done

#process other argument
case "$1" in
   listinst)   mode=$1; shift 1;;
   addinst)    test -z $2 && lack_para "PORT" || INST_PORT=$2
               test -z $DEFINE_MYSQLDATA && lack_para "DATADIR"
               mode=$1; shift 2;;
   delinst)    test -z $2 && lack_para "PORT" || INST_PORT=$2
               mode=$1; shift 2;;
   status)     mode=$1
               test -z $2 && shift 1 || { INST_PORT=$2 && shift 2; }
               ;;
   start)      test -z $2 && lack_para "PORT" || INST_PORT=$2
               mode=$1; shift 2;;
   startall)   mode=$1; shift 1;;
   stop)       test -z $2 && lack_para "PORT" || INST_PORT=$2
               mode=$1; shift 2;;
   stopall)    mode=$1; shift 1;;
   restart)    test -z $2 && lack_para "PORT" || INST_PORT=$2
               mode=$1; shift 2;;
esac

if [ "$*" != "" ]; then
   echo "sdb_mysql_ctl: too many arguments: $*" >&2
   echo 'Try "sdb_mysql_ctl --help" for more information.'
   exit 64
fi

##################################
#    main entry
##################################

#get path
dir_name=`dirname $0`
if [[ ${dir_name:0:1} != "/" ]]; then
   BIN_PATH=$(pwd)/$dir_name  #relative path
else
   BIN_PATH=$dir_name         #absolute path
fi

cur_path=`pwd`
cd $BIN_PATH/../ && INSTALL_PATH=`pwd`
cd $cur_path >> /dev/null >&1

CONF_INST_PATH="${INSTALL_PATH}"

#check user
get_system_conf_file
check_user $mode

#enter operation mode
case $mode in
   listinst)      list_inst         ;;
   addinst)       add_inst          ;;
   delinst)       delete_inst       ;;
   status)        get_status        ;;
   start)         start_inst $INST_PORT || exit $?  ;;
   startall)      start_all         ;;
   stop)          stop_inst $INST_PORT || exit $?  ;;
   stopall)       stop_all          ;;
   restart)       restart_inst      ;;
esac

exit 0
