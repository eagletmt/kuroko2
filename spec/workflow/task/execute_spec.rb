require 'rails_helper'

module Kuroko2::Workflow::Task
  describe Execute do
    subject { Execute.new(node, token).execute }

    let(:context) { { 'ENV' => { 'NAME' => 'alice' } } }
    let(:node) { Kuroko2::Workflow::Node.new(:execute, shell) }

    let(:token) { create(:token, path: '/', script: 'execute:', context: context, job_definition: definition, job_instance: instance) }
    let(:execution) { Kuroko2::Execution.take }
    let(:definition) { create(:job_definition, script: "execute: echo HELLO\n") }
    let(:instance) do
      create(:job_instance, job_definition: definition).tap do |instance|
        instance.tokens.destroy
      end
    end

    context 'with shell script' do
      let(:shell) { 'echo $NAME' }

      specify do
        is_expected.to eq :pass

        expect(Kuroko2::Execution.all.size).to eq 1
        expect(execution.token).to eql token
        expect(execution.shell).to eq shell
        expect(execution.context['ENV']).to eq context['ENV']
      end
    end

    context 'with successfully completed' do
      before do
        create(:execution, token: token)
      end

      let(:shell) { 'echo $NAME' }

      specify do
        is_expected.to eq :next

        expect(Kuroko2::Execution.all.size).to eq 0
        expect(Kuroko2::Log.all.count).to eq 1
      end
    end

    context 'With TIMEOUT' do
      let(:shell) { 'sleep 5 && echo $NAME' }
      let(:pid) { 1 }
      let(:hostname) { 'myhost' }

      around do |example|
        Execute.new(node, token).execute

        execution = Kuroko2::Execution.of(token).take
        execution.update!(pid: pid)
        create(:worker, hostname: hostname, execution_id: execution.id)

        token.context['TIMEOUT'] = '1' # 1 minute
        Timecop.travel(2.minutes.since) { example.run }
      end

      it 'creates ProcessSignal' do
        expect { Execute.new(node, token).execute }.to change { Kuroko2::ProcessSignal.where(pid: execution.pid, hostname: hostname).count }.from(0).to(1)
      end
    end

    context 'if job passed EXPECTED_TIME' do
      let(:shell) { 'sleep 5 && echo $NAME' }

      context 'Without EXPECTED_TIME_NOTIFIED_AT' do
        around do |example|
          Execute.new(node, token).execute
          Kuroko2::Execution.of(token).take.update!(pid: 1)

          Timecop.travel((24.hours + 1.second).since) { example.run }
        end

        it 'alerts warnings' do
          expect(Kuroko2::Workflow::Notifier).to receive(:notify).with(:long_elapsed_time, token.job_instance)

          Execute.new(node, token).execute
          is_expected.to eq :pass
          Execute.new(node, token).execute
          expect(token.context['EXPECTED_TIME_NOTIFIED_AT']).to be_present
        end
      end

      context 'With EXPECTED_TIME_NOTIFIED_AT' do
        around do |example|
          Execute.new(node, token).execute
          Kuroko2::Execution.of(token).take.update!(pid: 1)

          Timecop.travel((24.hours + 1.second).since) do
            token.context['EXPECTED_TIME_NOTIFIED_AT'] = notified_time
            example.run
          end
        end

        context 'When EXPECTED_TIME_NOTIFIED_AT is now' do
          let(:notified_time) { Time.current }

          it 'does not alert warnings' do
            expect(Kuroko2::Workflow::Notifier).not_to receive(:notify)
            Execute.new(node, token).execute
            is_expected.to eq :pass
            Execute.new(node, token).execute
            expect(token.context['EXPECTED_TIME_NOTIFIED_AT']).to be_present
          end
        end

        context 'When EXPECTED_TIME_NOTIFIED_AT is 1 hours ago' do
          let(:notified_time) { (1.hours + 1.second).ago }

          it 'alert warnings' do
            expect(Kuroko2::Workflow::Notifier).to receive(:notify).with(:long_elapsed_time, token.job_instance)

            Execute.new(node, token).execute
            is_expected.to eq :pass
            Execute.new(node, token).execute
            expect(token.context['EXPECTED_TIME_NOTIFIED_AT']).to be_present
          end
        end
      end
    end

    context 'with MASKED_ENV' do
      let(:shell) { 'echo $NAME has password $PASSWORD' }
      let(:worker) { create(:worker) }

      before do
        context['MASKED_ENV'] = {
          'PASSWORD' => 'secret-value',
        }
      end

      it 'sets envrionment variable but does not log the value' do
        is_expected.to eq(:pass)
        executor = Kuroko2::Command::Shell.new(hostname: 'execute_spec', worker: worker)
        executor.execute
        expect(execution).to be_success
        expect(execution.output).to eq("alice has password secret-value\n")
        all_messages = instance.logs.map(&:message).join("\n")
        expect(all_messages).to include('NAME')
        expect(all_messages).to include('alice')
        expect(all_messages).to include('PASSWORD')
        expect(all_messages).to_not include('secret-value')
      end
    end
  end
end
