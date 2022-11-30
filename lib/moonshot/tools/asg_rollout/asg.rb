module Moonshot
  module Tools
    class ASGRollout
      # Abstration layer with AWS Auto Scaling Groups, for the Rollout tool.
      class ASG
        attr_reader :name

        def initialize(name)
          @name = name
          @last_seen_ids = []
        end

        def current_max_and_desired
          asg = load_asg

          [asg.max_size, asg.desired_capacity]
        end

        def set_max_and_desired(max, desired)
          autoscaling.update_auto_scaling_group(
            auto_scaling_group_name: @name,
            max_size: max,
            desired_capacity: desired)
        end

        def non_conforming_instances
          asg = load_asg

          asg.instances
             .select { |i| i.launch_configuration_name != asg.launch_configuration_name }
             .map(&:instance_id)
        end

        def wait_for_new_instance
          # Query the ASG until an instance appears which is not in
          # @last_seen_ids, then add it to @last_seen_ids and return
          # it.
          previous_ids = @last_seen_ids

          loop do
            load_asg

            new_ids = @last_seen_ids - previous_ids
            previous_ids = @last_seen_ids

            unless new_ids.empty?
              @last_seen_ids << new_ids.first
              return new_ids.first
            end

            sleep 3
          end
        end

        def detach_instance(id, decrement:)
          # Store the current instance IDs for the next call to wait_for_new_instance.
          load_asg

          resp = autoscaling.detach_instances(
            auto_scaling_group_name: @name,
            instance_ids: [id],
            should_decrement_desired_capacity: decrement)

          activity = resp.activities.first
          unless activity
            raise 'Did not receive Activity from DetachInstances call!'
          end

          # Wait for the detach activity to complete:
          loop do
            resp = autoscaling.describe_scaling_activities(
              auto_scaling_group_name: @name)

            current_status = resp.activities
                                 .find { |a| a.activity_id == activity.activity_id }
                                 .status_code

            case current_status
            when 'Failed', 'Cancelled'
              raise 'Detachment did not complete successfully!'
            when 'Successful'
              return
            end

            sleep 1
          end
        end

        def instance_health(id)
          elb_status = nil
          elb_status = elb_instance_state(id) if elb_name

          InstanceHealth.new(asg_instance_state(id), elb_status)
        end

        private

        def asg_instance_state(id)
          resp = autoscaling.describe_auto_scaling_instances(
            instance_ids: [id])

          instance_info = resp.auto_scaling_instances.first
          return 'Missing' unless instance_info

          instance_info.lifecycle_state
        end

        def elb_instance_state(id)
          resp = loadbalancing.describe_instance_health(
            load_balancer_name: elb_name,
            instances: [
              { instance_id: id }
            ])

          instance_info = resp.instance_states.first
          unless instance_info
            raise "Failed to call DescribeInstanceHealth for #{id}!"
          end

          instance_info.state
        rescue Aws::ElasticLoadBalancing::Errors::InvalidInstance
          # We expect the instance to be in an ELB, eventually.
          'Missing'
        end

        def autoscaling
          @autoscaling ||= Aws::AutoScaling::Client.new
        end

        def loadbalancing
          @loadbalancing ||= Aws::ElasticLoadBalancing::Client.new
        end

        def load_asg
          resp = autoscaling.describe_auto_scaling_groups(
            auto_scaling_group_names: [@name])

          if resp.auto_scaling_groups.empty?
            raise "Failed to call DescribeAutoScalingGroups for #{@name}!"
          end

          asg = resp.auto_scaling_groups.first
          @last_seen_ids = asg.instances.map(&:instance_id)

          asg
        end

        def elb_name
          return @elb_name if @elb_name

          asg = load_asg
          if asg.load_balancer_names.size > 1
            raise 'ASGRollout does not support configurations with multiple ELBs!'
          end

          @elb_name ||= asg.load_balancer_names.first
        end
      end
    end
  end
end
