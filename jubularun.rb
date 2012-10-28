#!/usr/bin/env ruby
# coding: utf-8
# License: Eclipse Public License 1.0
# Copyright Niklaus Giger, 2011, niklaus.giger@member.fsf.org

require 'fileutils'
require 'tempfile'
require "#{File.dirname(__FILE__)}/helpers"
require "#{File.dirname(__FILE__)}/jubulaoptions"
require 'rexml/document'
include REXML

class JubulaRun

public
    JubulaOptions::Fields.each { 
      |x|
    eval(
      %(
      def #{x}
	@#{x}
      end
	)
    )
  }
    
  @@myFail = true

  # pass JubulaOptions like this: :autid = 'myAutId', :instDest = '/opt/myInstallation'
  def initialize(options = nil) 
    JubulaOptions::Fields.each { |x| eval("@#{x} = JubulaOptions::#{x}") }
    options.each { |opt, val| eval( "@#{opt} = '#{val}'") } if options
	["#{@jubulaHome}/server/autagent*",
	"#{@jubulaHome}/#{@application}/#{@application}*",
	"#{@jubulaHome}/#{@application}/testexec*",
	"#{@jubulaHome}/#{@application}/dbtool*",
	].each { 
	  |file|
		if Dir.glob(file.gsub('"','')).size == 0
			puts("Jubula not correctly installed in #{@jubulaHome}")
			puts("We could not find the needed application: #{file}")
			exit 1
	  end
	}
    [@instDest, @testResults, @dataDir].each { #  @data,
      |x|
	FileUtils.rm_rf(x, :verbose => true, :noop => @dryRun)
	FileUtils.makedirs(x, :verbose => true, :noop => @dryRun)
    }
    ENV['TEST_UPV_WORKSPACE'] = @workspace
  end
  
  def autoInstall
    FileUtils.rm_rf(@instDest, :verbose => true, :noop => @dryRun)
    short = wgetIfNotExists(@installer)
    if MACOSX_REGEXP.match(RUBY_PLATFORM)
      saved = Dir.pwd
      FileUtils.makedirs(@instDest)
      Dir.chdir(@instDest)
      system("unzip -q #{saved}/#{short}")
      Dir.chdir(saved)
    else
      doc   = Document.new(File.new(@auto_xml))
      path  = XPath.first(doc, "//installpath" )
      path.text= @instDest
      file = Tempfile.new('auto_inst.xml')
      file.write(doc.to_s)
      file.rewind
      file.close
      system("java -jar #{short} #{file.path}")
      # file.unlink    # deletes the temp file
    end
 end
  
 def dbSpec
    "-dbscheme '#{@dbscheme}' -dburl '#{@dburl}' -dbuser '#{@dbuser}' -dbpw '#{@dbpw}' "
 end
 
 def useH2(where = @data)
  @data     = where
  @dbscheme = 'Default Embedded (H2)'
  @dburl    = "jdbc:h2:#{where}/database/embedded;MVCC=TRUE;AUTO_SERVER=TRUE;DB_CLOSE_ON_EXIT=FALSE"
  @dbuser   = 'sa'
  @dbpw     = ''
 end
 
  def prepareRcpSupport
    savedDir = Dir.pwd
    Dir.chdir(@instDest) if !DryRun
	cmd = "#{@jubulaHome}/rcp-support.zip"
	if WINDOWS_REGEXP.match(RUBY_PLATFORM)
	  cmd = "#{File.expand_path(File.dirname(__FILE__))}/7z x -y #{cmd} > test-unzip.log"
	  cmd.gsub!('\\', '\\\\')
	else 
	  cmd = "unzip -q #{cmd}"
	end
    system(cmd) if Dir.glob("#{@instDest}/plugins/org.eclipse.jubula.rc.rcp_*/*").size == 0
    Dir.chdir(savedDir) if !DryRun
  end
  
  def rmTestcases(tc = @project, version = @version) 
    system("#{@jubulaHome}/#{@application}/dbtool -delete #{project} #{version}     #{dbSpec}", @@myFail)
  end
  
  def loadTestcases(xmlFile = "#{project}_#{version}.xml")
    ["unbound_modules_swt", "unbound_modules_concrete",  "unbound_modules_rcp"].each{ 
      |tcModule|
      tcs = Dir.glob("#{@jubulaHome}/examples/testCaseLibrary/#{tcModule}_*.xml")
      if tcs.size != 1
	puts "Should have found exactly 1 one file. Got #{tcs.inspect}"
	exit 1
      end
      system("#{@jubulaHome}/#{@application}/dbtool -import #{tcs[0]} #{dbSpec}", @@myFail)
      } # if !File.exists?("#{@data}/database/embedded.data.db")
    res = system("#{@jubulaHome}/#{@application}/dbtool -import #{xmlFile} #{dbSpec}")
  end
  
  def startAgent(sleepTime = 15)
    cmd = "#{@jubulaHome}/server/autagent"
    # Next few lines needed for MacOSX and Jubula 5.2 or 6.0
    [ '.app/Contents/MacOS/JavaApplicationStub',
      '.app/Contents/MacOS/autagent'].each {
	|tst|
      cmd = cmd+tst if Dir.glob(cmd+tst).size == 1
      }
	cmd = "#{cmd} -p #{portNumber}"
	if WINDOWS_REGEXP.match(RUBY_PLATFORM)
		res = system("start #{cmd}")
	else
		res = system("#{cmd} &")
	end
	if !res then puts "failed. exiting"; exit(3); end
    sleep(sleepTime) # give the agent time to start up (sometimes two seconds were okay)
  end
  
  def startAUT(sleepTime = 30)
	@@nrRun ||= 0
	@@nrRun += 1
	log = "#{@testResults}/test-console-#{@@nrRun}.log"
	cmd = "#{@jubulaHome}/server/autrun --workingdir #{@testResults} -rcp --kblayout #{@kblayout} -i #{@autid} --exec #{@wrapper} --generatename true --autagentport #{@portNumber}"
	if WINDOWS_REGEXP.match(RUBY_PLATFORM)
	   cmd = "start #{cmd}"
	else 
	  cmd += " 2>&1 | tee #{log} &"
	end
    res = system(cmd)
    if !res then puts "failed. exiting"; exit(3); end
    puts("Sleeping for #{sleepTime} after startAUT")
    sleep(sleepTime)
  end
  
  def stopAgent(sleepTime = 3)
    cmd = "#{@jubulaHome}/server/stopautagent"
    cmd += '.app/Contents/MacOS/JavaApplicationStub' if MACOSX_REGEXP.match(RUBY_PLATFORM)
    system("#{cmd} -p #{@portNumber} -stop", @@myFail)
    sleep(sleepTime)
  end

  def runTestsuite(testsuite = @testsuite)
    res = system("#{@jubulaHome}/#{@application}/testexec -project  #{project} -port #{@portNumber} " +
	  "-version #{@version} -testsuite '#{testsuite}' -server #{server} -autid #{@autid} "+
	  "-resultdir #{@testResults} -language  #{@kblayout} #{dbSpec} " +
	  "-datadir #{@dataDir} -data #{@data}")
    puts "runTestsuite  #{testsuite} returned #{res.inspect}"
#    system("import #{testsuite}_#{res.to_s}.png", @@myFail)
    res
  end
  
  def runOneTestcase(testcase)
    startAgent
    startAUT(10)
    okay = runTestsuite(testcase)
    stopAgent(10)
    okay
  end

  def run(testsuite=@testsuite)
    useH2
    loadTestcases
    genWrapper
    autoInstall
    prepareRcpSupport
    startAgent
    startAUT
    res = runTestsuite(testsuite)
    stopAgent
    res
  end

  def genWrapper
    wrapper = "#{JubulaOptions.wrapper}"
    exe  = File.expand_path(exeFile)
    exe += '.app/Contents/MacOS/starter-mac' if MACOSX_REGEXP.match(RUBY_PLATFORM)
    doc = "#{exe} #{vm.eql?('java') ? "" : " -vm #{vm}"} -clean -data #{@dataDir} -vmargs #{vmargs}"
    File.open(wrapper, 'w') {|f| f.puts(doc) }
    FileUtils.chmod(0744, wrapper)
    puts "#{dryRun ? 'Would create' : 'Created'} wrapper script #{wrapper} with content"
    puts doc
  end
  
end

if $0 == __FILE__
  JubulaOptions::parseArgs
  JubulaOptions::dryRun == true ? DryRun = true : DryRun = false

  # run with defaults
  jubula = JubulaRun.new
  jubula.run
end
