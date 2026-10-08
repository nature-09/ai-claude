package com.company.messenger.user;

import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByUsername(String username);

    boolean existsByUsername(String username);

    boolean existsByRole(Role role);

    List<User> findByDepartmentIdAndActiveTrueOrderByNameAsc(Long departmentId);

    long countByDepartmentId(Long departmentId);

    @Query("""
            select u from User u
            where u.active = true
              and (lower(u.name) like lower(concat('%', :q, '%'))
                   or lower(u.username) like lower(concat('%', :q, '%'))
                   or lower(u.position) like lower(concat('%', :q, '%')))
            order by u.name
            """)
    List<User> search(@Param("q") String q, Pageable pageable);

    @Query("""
            select u from User u
            where :q = ''
               or lower(u.name) like lower(concat('%', :q, '%'))
               or lower(u.username) like lower(concat('%', :q, '%'))
            """)
    Page<User> adminSearch(@Param("q") String q, Pageable pageable);
}
