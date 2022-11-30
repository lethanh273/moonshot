describe 'Moonshot SSH features' do
  subject do
    c = Moonshot::ControllerConfig.new
    c.app_name = 'MyApp'
    c.environment_name = 'prod'
    c.ssh_config.ssh_user = 'joeuser'
    c.ssh_config.ssh_identity_file = '/Users/joeuser/.ssh/thegoods.key'
    c.ssh_command = 'cat /etc/passwd'
    Moonshot::Controller.new(c)
  end

  describe 'Moonshot::Controller#ssh' do
    before(:each) do
      ENV.delete('MOONSHOT_SSH_OPTIONS')
    end

    context 'normally' do
      it 'should execute an ssh command with proper parameters' do
        ts = instance_double(Moonshot::SSHTargetSelector)
        expect(Moonshot::SSHTargetSelector).to receive(:new).and_return(ts)
        expect(ts).to receive(:choose!).and_return('i-04683a82f2dddcc04')

        expect_any_instance_of(Moonshot::SSHCommandBuilder).to receive(:instance_ip).exactly(2)
          .and_return('123.123.123.123')
        expect(subject).to receive(:exec)
          .with('ssh -t -i /Users/joeuser/.ssh/thegoods.key -l joeuser 123.123.123.123 cat\ /etc/passwd') # rubocop:disable LineLength
        expect { subject.ssh }
          .to output("Opening SSH connection to i-04683a82f2dddcc04 (123.123.123.123)...\n")
          .to_stderr
      end
    end

    context 'when an instance id is given' do
      subject do
        c = super()
        c.config.ssh_instance = 'i-012012012012012'
        c
      end

      it 'should execute an ssh command with proper parameters' do
        expect_any_instance_of(Moonshot::SSHCommandBuilder).to receive(:instance_ip).exactly(2)
          .and_return('123.123.123.123')
        expect(subject).to receive(:exec)
          .with('ssh -t -i /Users/joeuser/.ssh/thegoods.key -l joeuser 123.123.123.123 cat\ /etc/passwd') # rubocop:disable LineLength
        expect { subject.ssh }
          .to output("Opening SSH connection to i-012012012012012 (123.123.123.123)...\n").to_stderr
      end
    end
  end
end
