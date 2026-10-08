package com.company.messenger.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.listener.ChannelTopic;
import org.springframework.data.redis.listener.RedisMessageListenerContainer;

import com.company.messenger.realtime.EventPublisher;

@Configuration
public class RedisConfig {

    @Bean
    public RedisMessageListenerContainer redisListenerContainer(RedisConnectionFactory factory, EventPublisher publisher) {
        RedisMessageListenerContainer container = new RedisMessageListenerContainer();
        container.setConnectionFactory(factory);
        container.addMessageListener(publisher, new ChannelTopic(EventPublisher.CHANNEL));
        return container;
    }
}
