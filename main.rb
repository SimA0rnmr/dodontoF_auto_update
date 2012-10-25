#! ruby -Ku
# -*- encoding: utf-8 -*-

class Main

  # ���C�u�������w��
  $LOAD_PATH << File.dirname(__FILE__)
  require 'libs'
  require 'net/ssh'
  require 'net/scp'
  require 'net/ftp'
  require 'fileutils'
  require 'find'
  require 'stricts'
  require 'yaml'
  #require 'validate_cf'


  # ��������
  def initialize
    logging("START : #{self.class.to_s}::#{__method__.to_s}" ,$info)
    
    # �J�����g�f�B���N�g����ύX
    if nil == ENV['OCRA_EXECUTABLE'] then 
      Dir.chdir(File.dirname(__FILE__))
    else
      Dir.chdir(File.dirname(ENV['OCRA_EXECUTABLE']))
    end
    
    # �p�����[�^�ݒ�
    params = YAML.load_file("./params.yml")
    
    #v_cf_proc = ValidateCf.new(params)
    
    #valid_flg = v_cf_proc.exec_validate
    
    $host = params["host"]
    $proto = params["proto"]
    $ssh_user = params["ssh_user"]
    $ssh_pass = params["ssh_pass"]
    $sudo_flg = params["sudo_flg"]
    $sudo_pass = params["sudo_pass"]
    $ftp_user = params["ftp_user"]
    $ftp_pass = params["ftp_pass"]
    @Ddtf_dir_path = check_dir(params["ddtf_dir"])
    @Work_dir_path = check_dir(params["work_dir"])
    
     
    # cp�R�}���h�C��(sudo��)
    if $sudo_flg == 1 then
      @Cp_cmd_exe = make_sudo($sudo_pass , $Cp_cmd) if $sudo_flg == 1
    elsif $sudo_flg == 0 then
      @Cp_cmd_exe = $Cp_cmd
    end
    
    logging("END   : " + self.class.to_s + "::" + __method__.to_s ,$info)
  end


  # �o�[�W�����A�b�v�O�i�K���
  def pre_ver_up
    logging("START : #{self.class.to_s}::#{__method__.to_s}" ,$info)

    # �ǂǂ�Ƃ�zip�t�@�C�����擾
    @new_ddtf_zip = File.expand_path(ARGV[0])

    # ���ʏ���
    begin
      Dir::mkdir($Client_work_dir)
    rescue Errno::EEXIST
      logging("\"#{File.expand_path($Client_work_dir)}\" is already exists",$warn)
    end

    begin
      Dir::mkdir($Client_zip_dir) if $proto.downcase=="ftp"
    rescue Errno::EEXIST
      logging("\"#{File.expand_path($Client_zip_dir)}\" is already exists",$warn)
    end

    # ssh,ftp��������
    case $proto.downcase
    when "ssh"
      self.pre_ver_up_ssh
    when "ftp"
      self.pre_ver_up_ftp
    end
    

    logging("END   : #{self.class.to_s}::#{__method__.to_s}" ,$info)
  end


  # �o�[�W�����A�b�v���
  def ver_up
    logging("START : #{self.class.to_s}::#{__method__.to_s}" ,$info)
    # ssh,ftp��������
    case $proto.downcase
    when "ssh"
      self.ver_up_ssh
    when "ftp"
      self.ver_up_ftp
    end
    logging("END   : #{self.class.to_s}::#{__method__.to_s}" ,$info)
  end



  # ���O�������s(SSH)
  def pre_ver_up_ssh
    logging("START : #{self.class.to_s}::#{__method__.to_s}" ,$info)

    @srv_working_dir_path = ''
    @srv_backup_dir_path = ''
    @srv_newver_dir_path = ''
    @srv_zip_path = ''

    # SSH�ڑ��i��ƃt�H���_�쐬�E�o�b�N�A�b�v�j
    Net::SSH.start($host, $ssh_user, :password => $ssh_pass) do |ssh|
    
      # ����Ɨp�t�H���_���쐬
      @srv_working_dir_path = check_dir(@Work_dir_path + delete_crlf(invoke(ssh , "#{$Date}")))
      invoke(ssh, "#{$Mkdir_cmd} #{@srv_working_dir_path}" ) 
      
      # �o�b�N�A�b�v�p�t�H���_�A�V�o�[�W�����p�t�H���_���쐬
      @srv_backup_dir_path = "#{@srv_working_dir_path}backup/"
      @srv_newver_dir_path = "#{@srv_working_dir_path}newver/"
      invoke(ssh, "#{$Mkdir_cmd} #{@srv_backup_dir_path}" )
      invoke(ssh, "#{$Mkdir_cmd} #{@srv_newver_dir_path}" )
      
      # �o�b�N�A�b�v���s(���C���f�B���N�g���A�R���t�B�O�j
      invoke(ssh, "#{$Comp_tar_cmd} #{@srv_backup_dir_path}dodontoF.tar #{@Ddtf_dir_path}*" )
      invoke(ssh, "#{@Cp_cmd_exe} #{@Ddtf_dir_path}src_ruby/config.rb #{@srv_backup_dir_path}config.rb" )
    end

    # SCP�ڑ��i�V�o�[�W������zip�t�@�C���𑗐M�j
    Net::SCP.start($host, $ssh_user, :password => $ssh_pass) do|scp|
      @srv_zip_path =  "#{@srv_newver_dir_path}#{File.basename(@new_ddtf_zip)}"
      channel = scp.upload(@new_ddtf_zip , @srv_zip_path )
      channel.wait
    end

    # SSH�ڑ��izip�𓀁j
    Net::SSH.start($host, $ssh_user, :password => $ssh_pass) do |ssh|
      # zip��
      invoke_nomsg(ssh, "#{$Exp_zip_cmd} #{@srv_newver_dir_path} #{@srv_zip_path}" )
    end

    # SCP�ڑ��i�V���R���t�B�O���`�j
    Net::SCP.start($host, $ssh_user, :password => $ssh_pass) do|scp|
      channel = scp.download( "#{@srv_newver_dir_path}#{$Def_ddtf_path}#{$Conf_file_from_ddtf_path}" , "#{$Client_work_dir}01_new_config.rb" )
      channel.wait
      channel = scp.download( "#{@srv_backup_dir_path}config.rb" , "#{$Client_work_dir}01_old_config.rb" )
      channel.wait
    end
    

    # SSH�ڑ��i���O�C�����b�Z�[�W�AuploadImageSpace,saveData�o�b�N�A�b�v�j
    Net::SSH.start($host, $ssh_user, :password => $ssh_pass) do |ssh|
      open( "#{$Client_work_dir}01_old_config.rb" , "r:#{$enc_str}" ) { |file|
        lines = file.readlines
        # ���O�C�����b�Z�[�W�o�b�N�A�b�v
        @login_message_file = lines.find{|elem| /^\$loginMessageFile.*/ =~ elem}.split("=")[1]
        @login_message_file = trim_rbstr(@login_message_file)
        invoke(ssh, "#{@Cp_cmd_exe} #{@Ddtf_dir_path}#{@login_message_file} #{@srv_backup_dir_path}#{@login_message_file}" )

        # imageUploadSpace�o�b�N�A�b�v
        img_dir_path = lines.find{|elem| /^\$imageUploadDir.*/ =~ elem}.split("=")[1]
        img_dir_path = trim_rbstr(img_dir_path)
        invoke(ssh, "#{$Cd_cmd} #{@Ddtf_dir_path} ; #{$Comp_tar_cmd} #{@srv_backup_dir_path}img.tar #{img_dir_path}/* ")

        # saveData�o�b�N�A�b�v
        save_dir_path = lines.find{|elem| /^\$SAVE_DATA_DIR.*/ =~ elem}.split("=")[1]   
        save_dir_path = trim_rbstr(save_dir_path)
        invoke(ssh, "#{$Cd_cmd} #{@Ddtf_dir_path} ; #{$Comp_tar_cmd} #{@srv_backup_dir_path}save.tar #{save_dir_path}/* ")
      }
    end
    
    
    

    # ���A�g�t�@�C���쐬
    File.open("#{$Client_work_dir}working.yml" , "w:#{$enc_str}" ) do|f|
      f.puts "srv_working_dir: #{@srv_working_dir_path}" 
      f.puts "login_message_file: #{@login_message_file}"
      f.close
    end

    logging("END   : #{self.class.to_s}::#{__method__.to_s}" ,$info)
  end


  # ���O�������s(FTP)
  def pre_ver_up_ftp
    logging("START : #{self.class.to_s}::#{__method__.to_s}" ,$info)

    # ������zip����
    ore_unzip(@new_ddtf_zip , $Client_zip_dir)

    # ���s�̃R���t�B�O���擾
    Net::FTP.open($host, $ftp_user, $ftp_pass) do |ftp|
      ftp.passive = true
      ftp.getbinaryfile( "#{@Ddtf_dir_path}src_ruby/config.rb" , "#{$Client_work_dir}01_old_config.rb" )
      ftp.close
    end

    # �V�����R���t�B�O�̐��`������̏ꏊ�ɃR�s�[
    FileUtils.copy( "#{$Client_zip_dir}#{$Def_ddtf_path}#{$Conf_file_from_ddtf_path}" , "#{$Client_work_dir}01_new_config.rb" )

    logging("END   : #{self.class.to_s}::#{__method__.to_s}" ,$info)
  end


  # �o�[�W�����A�b�v���s(SSH)
  def ver_up_ssh
    logging("START : #{self.class.to_s}::#{__method__.to_s}" ,$info)
    
    
    # �A�g�f�B���N�g�����擾
    $srv_working_dir = YAML.load_file("#{$Client_work_dir}working.yml")["srv_working_dir"]

    # SCP�ڑ��i�V�R���t�B�O����ƃt�H���_�ɑ��M�j
    Net::SCP.start($host, $ssh_user, :password => $ssh_pass) do|scp|
      channel = scp.upload( "#{$Client_work_dir}01_new_config.rb" , "#{$srv_working_dir}newver/config.rb" )
      channel.wait
    end

    # SSH�ڑ��i�V���̔z�u�j
    Net::SSH.start($host, $ssh_user, :password => $ssh_pass) do |ssh|
      invoke(ssh, "#{@Cp_cmd_exe} #{$srv_working_dir}newver/#{$Def_ddtf_path}* #{@Ddtf_dir_path}" )
      invoke(ssh, "#{@Cp_cmd_exe} #{$srv_working_dir}newver/config.rb #{@Ddtf_dir_path}#{$Conf_file_from_ddtf_path}" )
    end
    logging("END   : #{self.class.to_s}::#{__method__.to_s}" ,$info)
  end



  # �o�[�W�����A�b�v���s(ftp)
  def ver_up_ftp
    logging("START : #{self.class.to_s}::#{__method__.to_s}" ,$info)

    @file_list = []
    @dir_list = []

    # �V�o�[�W�����̃f�B���N�g���^�t�@�C�����X�g���擾
    Dir.chdir( "#{$Client_zip_dir}#{$Def_ddtf_path}" )
    Find.find("./") do |f|
        if File.directory?(f)
        @dir_list <<   f unless f == "./"
      else
        logging("DirName  : #{File.dirname(f)}" , $debug)
        logging("FileName : #{File.basename(f)}" , $debug)
        @file_list << {:dir_name =>  File.dirname(f),:file_name => File.basename(f)}
      end
    end

    # �ǉ��f�B���N�g���쐬�A�t�@�C�����M
    if nil == ENV['OCRA_EXECUTABLE'] then 
      Dir.chdir(File.dirname(__FILE__))
    else
      Dir.chdir(File.dirname(ENV['OCRA_EXECUTABLE']))
    end
    Net::FTP.open($host,$ftp_user,$ftp_pass) do |ftp|
      ftp.passive = true
      ftp.binary = true

      # �f�B���N�g�������݂��Ȃ��ꍇ�ɍ쐬
      @dir_list.each do|dir|
        dir_path = correct_dir(dir.gsub(/^\./, @Ddtf_dir_path ))
        begin
          ftp.mkdir(dir_path)
        rescue
          logging("this Dir is already exists! : #{dir_path}",$debug)
        end
      end

      # �V�K�t�@�C�����M�i�㏑���j
      @file_list.each do |file|  
        src_file_path = correct_dir( "#{$Client_zip_dir}#{file[:dir_name].gsub(/^\./,$Def_ddtf_path)}/#{file[:file_name]}")
        dst_file_path = correct_dir( "#{file[:dir_name].gsub(/^\./,@Ddtf_dir_path)}/#{file[:file_name]}")
        logging("ftp_src_file : #{src_file_path}" , $debug)
        logging(" ->ftp_dst_file : #{dst_file_path}" , $debug)
        ftp.put( File::expand_path(src_file_path) ,  dst_file_path)
      end
      
      # �V�K�R���t�B�O���M
      ftp.puttextfile( "#{$Client_work_dir}01_new_config.rb" , "#{@Ddtf_dir_path}src_ruby/config.rb" )
      ftp.close
    end
    logging("END   : #{self.class.to_s}::#{__method__.to_s}" ,$info)
  end




  # �R���t�B�O�t�@�C���C��
  def make_conf
    logging("START : #{self.class.to_s}::#{__method__.to_s}" ,$info)
  
    # �V�o�[�W�����t�@�C�������l�[��
    File.rename( "#{$Client_work_dir}01_new_config.rb" , "#{$Client_work_dir}01_new_config.rb.bak" )
  
    # old�t�@�C���̏����擾
    old_params = [] 
    open( "#{$Client_work_dir}01_old_config.rb" , "r:#{$enc_str}" ) { |file|
      # �ύX�Ώەϐ�����擾(version�֘A�AdiceBotOrder�ȊO�j
      old_params = file.readlines.select{|elem| /^\$.*/ =~ elem and /^\$versionOnly|^\$versionDate|^\$version|^\$diceBotOrder/ !~ elem}
    }

    # new�t�@�C����old�t�@�C�����}�[�W
    base_str = ""
    open( "#{$Client_work_dir}01_new_config.rb.bak" , "r+b:#{$enc_str}" ) { |file|
      while l = file.gets
        flg = true
        old_params.each do |old_param|
          if l.split("=")[0] == old_param.split("=")[0] then
            base_str << old_param
            flg = false
          end
        end
        if flg
          base_str << l
        end
      end
    }

    # �Vnew�o�[�W�����t�@�C���쐬
    open( "#{$Client_work_dir}01_new_config.rb" , "w+b:#{$enc_str}" ) {|file|
      file.write(base_str)
    }

    logging("END   : #{self.class.to_s}::#{__method__.to_s}" ,$info)
  end
  
  
  


end
