require 'spec_helper'

require 'cli'

describe Bosh::Cli::Command::JobManagement do
  let(:command) { described_class.new }
  let(:deployment) { 'dep1' }
  let(:manifest_yaml) { Psych.dump(deployment_manifest) }
  let(:director) { instance_double('Bosh::Cli::Client::Director') }

  before(:each) do
    allow(director).to receive(:change_job_state).and_return(:done, nil, '')
    allow(command).to receive_messages(target: 'http://bosh.example.com')
    allow(command).to receive_messages(logged_in?: true)
    allow(command).to receive_messages(inspect_deployment_changes: false)
    allow(command).to receive(:nl)
    allow(command).to receive_messages(confirmed?: true)
    allow(command).to receive(:director).and_return(director)
    allow(command).to receive(:prepare_deployment_manifest).and_return(deployment_manifest)
    allow(command).to receive(:prepare_deployment_manifest).with(yaml: true).and_return(manifest_yaml)
  end

  let(:deployment_manifest) do
    {
        'name' => deployment,
        'jobs' => [
            {
                'name' => 'dea',
                'instances' => instance_count
            }
        ]
    }
  end

  shared_examples_for 'a command which modifies the vm state' do |options|
    method_name = options.fetch(:with) { raise ArgumentError.new('You need to specify which method the command' +
                                                                     ' uses to modify the VM state. (:start_job)') }
    verb = options.fetch(:verb) { raise ArgumentError.new('You need to specify which verb the command describes' +
                                                              ' itself with. ("start")') }
    past_verb = options.fetch(:past_verb) { raise ArgumentError.new('You need to specify which past tense verb the' +
                                                                        ' command describes itself with. ("started")') }
    extra_task_report_info = options.fetch(:extra_task_report_info) {raise ArgumentError.new('You need to specify any' +
                                                                ' extra information given to the task report.') }
    new_state = options.fetch(:new_state) { past_verb }
    operation_description_extra = options.fetch(:operation_description_extra) { '' }

    it_requires_logged_in_user ->(command) { command.public_send(method_name, 'dea') }

    it 'complains if the job does not exist' do
      expect {
        command.public_send(method_name, 'some_fake_job', '0')
      }.to raise_error(Bosh::Cli::CliError, "Job `some_fake_job' doesn't exist")
    end

    it 'does not allow both --hard and --soft options' do
      command.options[:hard] = true
      command.options[:soft] = true

      expect {
        command.public_send(method_name, 'dea', '0')
      }.to raise_error(Bosh::Cli::CliError, 'Cannot handle both --hard and --soft options, please choose one')
    end

    it 'errors if --hard or --soft options are supplied for non stop-operation' do
      command.options[:hard] = true

      next if method_name == :stop_job

      expect {
        command.public_send(method_name, 'dea', '0')
      }.to raise_error(Bosh::Cli::CliError, "--hard and --soft options only make sense for `stop' operation")
    end

    context 'if an index is supplied' do
      it 'tells the user what it is about to do' do
        expect(command).to receive(:say).with("You are about to #{verb} dea/0#{operation_description_extra}")
        expect(command).to receive(:say).with("Performing `#{verb} dea/0#{operation_description_extra}'...")
        expect(command).to receive(:say).with %r{\ndea/0 has been #{past_verb}}

        command.public_send(method_name, 'dea', '0')
      end
    end

    context 'if an index is not supplied' do
      it 'tells the user what it is about to do' do
        if instance_count == 1
          expect(command).to receive(:say).with("You are about to #{verb} dea/0#{operation_description_extra}")
          expect(command).to receive(:say).with("Performing `#{verb} dea/0#{operation_description_extra}'...")
          expect(command).to receive(:say).with %r{\ndea/0 has been #{past_verb}}
          command.public_send(method_name, 'dea')
        else
          expect {
            command.public_send(method_name, 'dea')
          }.to raise_error(Bosh::Cli::CliError, 'You should specify the job index. There is more than one instance of this job type.')
        end
      end
    end

    context 'if the bosh CLI is running interactively' do
      before do
        command.options[:non_interactive] = false
      end

      context 'when there has been a change in the manifest locally' do
        before do
          allow(command).to receive_messages(inspect_deployment_changes: true)
        end

        context 'when we do not force the command' do
          it 'refuses if there are job changes' do
            expect {
              command.public_send(method_name, 'dea', '0')
            }.to raise_error(Bosh::Cli::CliError, "Cannot perform job management when other deployment " +
                "changes are present. Please use `--force' to override.")
          end
        end
      end

      context 'when there has not been a change in the manifest locally' do
        before do
          allow(command).to receive_messages(inspect_deployment_changes: false)
        end

        context 'if we do not confirm the command' do
          before do
            allow(command).to receive(:say)
            allow(command).to receive_messages(confirmed?: false)
          end

          it 'cancels the deployment' do
            expect {
              command.public_send(method_name, 'dea', '0')
            }.to raise_error(Bosh::Cli::GracefulExit, 'Deployment canceled')
          end
        end

        context 'if an index is supplied' do
          it 'changes the job state' do
            expect(director).to receive(:change_job_state).with(deployment, manifest_yaml, 'dea', '0', new_state)
            command.public_send(method_name, 'dea', '0')
          end

          it 'reports back on the task report' do
            allow(director).to receive_messages(change_job_state: %w(done 23))
            expect(command).to receive(:task_report).with('done', '23', "dea/0 has been #{past_verb}#{extra_task_report_info}")
            command.public_send(method_name, 'dea', '0')
          end
        end

        context 'if an index is not supplied' do
          it 'changes the job state' do
            if instance_count == 1
              expect(director).to receive(:change_job_state).with(deployment, manifest_yaml, 'dea', '0', new_state)
              command.public_send(method_name, 'dea')
            else
              expect {
                command.public_send(method_name, 'dea')
              }.to raise_error(Bosh::Cli::CliError, 'You should specify the job index. There is more than one instance of this job type.')
            end
          end

          it 'reports back on the task report' do
            if instance_count == 1
              allow(director).to receive_messages(change_job_state: %w(done 23))
              expect(command).to receive(:task_report).with('done', '23', "dea/0 has been #{past_verb}#{extra_task_report_info}")
              command.public_send(method_name, 'dea')
            else
              expect {
                command.public_send(method_name, 'dea')
              }.to raise_error(Bosh::Cli::CliError, 'You should specify the job index. There is more than one instance of this job type.')
            end
          end
        end
      end
    end
  end

  context 'if there is only one job of the specified type in the deployment' do
    let(:instance_count) { 1 }

    describe 'starting a job' do
      it_behaves_like 'a command which modifies the vm state', with: :start_job,
                      verb: 'start', past_verb: 'started', extra_task_report_info: ''
    end

    describe 'detaching a job' do
      before do
        command.options[:hard] = true
      end

      it_behaves_like 'a command which modifies the vm state', with: :stop_job,
                      verb: 'stop', past_verb: 'detached',
                      extra_task_report_info: ', VM(s) powered off',
                      operation_description_extra: ' and power off its VM(s)'
    end

    describe 'stop a job' do
      before do
        command.options[:hard] = false
      end

      it_behaves_like 'a command which modifies the vm state', with: :stop_job,
                      verb: 'stop', past_verb: 'stopped', extra_task_report_info: ', VM(s) still running'
    end

    describe 'restart a job' do
      it_behaves_like 'a command which modifies the vm state', with: :restart_job,
                      verb: 'restart', past_verb: 'restarted', extra_task_report_info: '', new_state: 'restart'
    end

    describe 'recreate a job' do
      it_behaves_like 'a command which modifies the vm state', with: :recreate_job,
                      verb: 'recreate', past_verb: 'recreated', extra_task_report_info: '', new_state: 'recreate'
    end
  end

  context 'if there are many jobs of the specified type in the deployment' do
    let(:instance_count) { 100 }

    describe 'starting a job' do
      it_behaves_like 'a command which modifies the vm state', with: :start_job,
                      verb: 'start', past_verb: 'started', extra_task_report_info: ''
    end

    describe 'detaching a job' do
      before do
        command.options[:hard] = true
      end

      it_behaves_like 'a command which modifies the vm state', with: :stop_job,
                      verb: 'stop', past_verb: 'detached',
                      extra_task_report_info: ', VM(s) powered off',
                      operation_description_extra: ' and power off its VM(s)'
    end

    describe 'stop a job' do
      before do
        command.options[:hard] = false
      end

      it_behaves_like 'a command which modifies the vm state', with: :stop_job,
                      verb: 'stop', past_verb: 'stopped', extra_task_report_info: ', VM(s) still running'
    end

    describe 'restart a job' do
      it_behaves_like 'a command which modifies the vm state', with: :restart_job,
                      verb: 'restart', past_verb: 'restarted', extra_task_report_info: '', new_state: 'restart'
    end

    describe 'recreate a job' do
      it_behaves_like 'a command which modifies the vm state', with: :recreate_job,
                      verb: 'recreate', past_verb: 'recreated', extra_task_report_info: '', new_state: 'recreate'
    end
  end
end
